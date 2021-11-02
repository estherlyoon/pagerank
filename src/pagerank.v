`include "pr_constants.v"

module PageRank(
	input clk,
	input rst,
	
	output reg [15:0] arid_m,
	output reg [63:0] araddr_m,
	output reg [7:0]  arlen_m,
	output reg [2:0]  arsize_m,
	output reg        arvalid_m,
	input             arready_m,
	
	input [15:0]  rid_m,
	input [511:0] rdata_m,
	input [1:0]   rresp_m,
	input         rlast_m,
	input         rvalid_m,
	output reg    rready_m,
	
	output reg [15:0] awid_m,
	output reg [63:0] awaddr_m,
	output reg [7:0]  awlen_m,
	output reg [2:0]  awsize_m,
	output reg        awvalid_m,
	input             awready_m,
	
	output reg [15:0]  wid_m,
	output reg [511:0] wdata_m,
	output reg [63:0]  wstrb_m,
	output reg         wlast_m,
	output reg         wvalid_m,
	input              wready_m,
	
	input [15:0] bid_m,
	input [1:0]  bresp_m,
	input        bvalid_m,
	output reg   bready_m,
	
	input        softreg_req_valid,
	input        softreg_req_isWrite,
	input [31:0] softreg_req_addr,
	input [63:0] softreg_req_data,
	
	output        softreg_resp_valid,
	output [63:0] softreg_resp_data

	//input [31:0] count0,
	//input [31:0] count1,
	//input [31:0] count2
);

reg [63:0] count = 0;
always @(posedge clk)
	count <= count + 1;

// length of integers in bits
localparam INT_W = 64;
localparam BYTE = 8;
// precision of fixed-point values
localparam PREC = 16; 

// pr states
localparam WAIT = 0;
localparam READ_VERT = 1;
localparam READ_INEDGES = 2;
localparam READ_PR = 3;
localparam CONTROL = 4;
reg wait_priority = 0;
reg [7:0] pr_state = 0;

// divider
reg init_din = 0;
reg init_div_over = 0;
reg din = 0;
wire dvalid = init_din || din;
reg dset = 0;
reg [INT_W-1:0] dividend;
reg [INT_W/2-1:0] divisor;
wire [INT_W/2-1:0] quotient;
wire [INT_W/2-1:0] remainder;
wire div0, ovf, dout;

reg [INT_W/2-1:0] last_quotient = 0;

always @(posedge clk) begin
	if(dout)
		last_quotient <= quotient;
end

div_uu #(INT_W) div (
	.clk(clk),
	.ena(1'b1),
	.iready(dvalid),
	.z(dividend),
	.d(divisor),
	.q(quotient),
	.s(remainder),
	.div0(div0), // division by zero
	.ovf(ovf), // overflow
	.oready(dout) // result ready
);

reg v_rready;
reg [511:0] v_rdata;
reg v_odata_req;
reg [7:0] v_base;
reg [7:0] v_bounds;
wire v_oready;
wire [INT_W*2-1:0] v_odata;

ReadBuffer #(
	.FULL_WIDTH(512),
	.WIDTH(INT_W*2)
) v_buffer (
	clk,
	v_rready,
	v_rdata,
	v_odata_req, // get data out when FIFO isn't full
	v_base,
	v_bounds,
	v_oready, // fed into FIFO
	v_odata // feed into FIFO
);

reg ie_rready;
reg [511:0] ie_rdata;
reg ie_odata_req;
reg [7:0] ie_base;
reg [7:0] ie_bounds;
wire ie_oready;
wire [INT_W-1:0] ie_odata;

ReadBuffer #(
	.FULL_WIDTH(512),
	.WIDTH(INT_W)
) ie_buffer (
	clk,
	ie_rready,
	ie_rdata,
	ie_odata_req,
	ie_base,
	ie_bounds,
	ie_oready,
	ie_odata
);

reg pr_rready;
reg [511:0] pr_rdata;
wire [63:0] pr_odata;
reg [63:0] pr_raddr;
reg [63:0] pr_waddr;

// total number of PageRank iterations to complete
reg [31:0] total_rounds;
// number of iterations completed so far
reg [31:0] round = 0;
// total runs of PageRank (do total_rounds per run)
reg [31:0] total_runs = 1;
reg next_run = 0;

// vertex FIFO signals
reg vert_fifo_wrreq;
reg [127:0] vert_fifo_in;
wire vert_fifo_full;
wire vert_fifo_rdreq;
wire [127:0] vert_fifo_out;
wire vert_fifo_empty;
 
// in-edge vertices FIFO signals
reg inedge_fifo_wrreq;
reg [63:0] inedge_fifo_in;
wire inedge_fifo_full;
wire inedge_fifo_rdreq;
wire [63:0] inedge_fifo_out;
wire inedge_fifo_empty;  

// PR data FIFO signals
reg pr_fifo_wrreq;
reg [63:0] pr_fifo_in;
wire pr_fifo_full;
wire pr_fifo_rdreq;
wire [63:0] pr_fifo_out;
wire pr_fifo_empty;

// divisor+dividend FIFO signals
reg din_fifo_wrreq;
reg [127:0] din_fifo_in;
wire din_fifo_full;
wire din_fifo_rdreq;
wire [127:0] din_fifo_out;
wire din_fifo_empty;
 
// div results FIFO signals
reg div_fifo_wrreq;
reg [63:0] div_fifo_in;
wire div_fifo_full;
wire div_fifo_rdreq;
wire [63:0] div_fifo_out;
wire div_fifo_empty;

// start of vertex array
reg [63:0] v_base_addr;
// current address to read vertex info from
reg [63:0] v_addr;
// total number of vertices
reg [63:0] n_vertices;
// how many vertices left to fetch
reg [63:0] vert_to_fetch;
// start of in-edge array
reg [63:0] ie_base_addr;
// current address to read in-edge # from
reg [63:0] ie_addr;
// total number of edges
reg [63:0] n_inedges;
// how many ie left to fetch
reg [63:0] ie_to_fetch;
// number of iterations of fetching per inedge stage
reg [3:0] ie_batch;
// the initial pagerank score, equal for all vertices
reg [INT_W-1:0] init_val;

reg [63:0] base_pr_raddr;
reg [63:0] base_pr_waddr;

// PageRank logic control signals
// I think it can always be ready for now (only need awvalid logic)
reg pr_wvalid = 1;
reg pr_awvalid = 0;
reg wbready = 1;
// indicates whether pr sum is done for a vertex
reg vdone = 0;
reg [INT_W-1:0] v_vcount = 0;
reg [INT_W-1:0] wb_vcount = 0;
reg [INT_W-1:0] n_outedge0;
reg [INT_W-1:0] n_outedge1;
reg [INT_W-1:0] ie_offset;
reg [INT_W-1:0] n_ie_left;
reg [INT_W-1:0] pr_sum = 0;
reg [INT_W-1:0] pagerank;
wire [INT_W-1:0] pr_dividend = pr_sum;

// set when pr address set
reg pr_pending = 0;
   
// read interface
always @(*) begin
	arid_m = 0;
	// must be 64-byte aligned
	araddr_m = 0;
	// arlen must not cross page boundaries
	arlen_m = 0;
	arsize_m = 3'b011; // 8 bytes
	arvalid_m = 0;

	rready_m = 1;

	v_rready = rvalid_m && (rid_m == 0);
	v_rdata = rdata_m;
	v_odata_req = !vert_fifo_full;
	vert_fifo_wrreq = v_oready;
	vert_fifo_in = v_odata;

	ie_rready = rvalid_m && (rid_m == 1);
	ie_rdata = rdata_m;
	ie_odata_req = !inedge_fifo_full;
	inedge_fifo_wrreq = ie_oready;
	inedge_fifo_in = ie_odata;

	pr_rready = rvalid_m && (rid_m == 2);
	pr_rdata = rdata_m;
	// this is fine because we only request a read when fifo !full
	pr_fifo_wrreq = pr_rready;
	pr_fifo_in = pr_odata;

    din_fifo_wrreq = vdone;
	din_fifo_in =  { pr_dividend, n_outedge0}; 

	div_fifo_wrreq = dout && init_div_over;
	div_fifo_in = quotient;

	// for debug
	/* if (!reads_done &&!print_done && wb_vcount + 1 == n_vertices) begin */
	/* 	arid_m = 3; */
	/* 	arlen_m = 0; */
	/* 	arvalid_m = 1; */
	/* 	araddr_m = base_pr_waddr + 16; */
	/* end */
	/* else begin */
	case(pr_state)
		READ_VERT: begin
			arid_m = 0;
			araddr_m = v_addr;
			arlen_m = 0;
			// only request reads when buffer is ready to accept data
			arvalid_m = !v_oready && (vert_to_fetch > 0);
		end
		READ_INEDGES: begin
			arid_m = 1;
			araddr_m = ie_addr;
			arlen_m = 0;
			arvalid_m = (round != 2) && !ie_oready && (ie_to_fetch > 0) && (ie_batch > 0) && !inedge_fifo_full;
		end
		READ_PR: begin
			arid_m = 2;
			araddr_m = pr_raddr;
			arlen_m = 0;
			arvalid_m = !pr_fifo_full && !inedge_fifo_empty && pr_pending;
		end
	endcase
	/* end */
end

// determine which part of line to write back
reg [63:0]  pr_strobe;
genvar g;
generate
for (g = 1; g <= BYTE; g = g + 1) begin
	always @(*) begin
		pr_strobe[BYTE*g-1:BYTE*(g-1)] = pr_waddr[5:3] == BYTE-g ? 8'hFF : 8'h00;
		wdata_m[INT_W*g-1:INT_W*(g-1)] = pr_waddr[5:3] == BYTE-g ? pagerank : 0;
	end
end
endgenerate

// write interface
always @(*) begin
	awid_m = 0;
	awaddr_m = pr_waddr;
	awlen_m = 0;
	awsize_m = 3'b011; // 8 bytes
	awvalid_m = pr_awvalid;

	wid_m = 0;
	wstrb_m = pr_strobe;
	wlast_m = 1;
	wvalid_m = pr_wvalid;

	bready_m = 1;
end

// output signals
reg sr_resp_valid = 0;
reg [63:0] sr_resp_data = 0;
assign softreg_resp_valid = sr_resp_valid;
assign softreg_resp_data = sr_resp_data;

reg [31:0] edge_cnt = 0;
reg [31:0] edge_fetched = 0;
reg [31:0] edge_to_fetch = 0;

// vertex stage signals
reg [1:0] vready = 0;
reg [1:0] vfirst = 1;

// in-edge stage signals
wire ie_getpr = arvalid_m && arready_m && (arid_m == 2);

localparam WAIT_VERT = 0;
localparam GET_VERT = 1;
localparam GET_SUM = 2;

assign vert_fifo_rdreq = (vready == GET_VERT) && (!vfirst || (v_vcount == 0)); // TODO test
assign inedge_fifo_rdreq = ie_getpr && round > 2;
assign pr_fifo_rdreq = (vready == GET_SUM) && (n_ie_left > 0) && (round > 2);
assign din_fifo_rdreq = !div_fifo_full;
assign div_fifo_rdreq = wbready;

// counts
reg [31:0] v_oready_cnt = 0;
reg [31:0] ie_oready_cnt = 0;
reg [31:0] pr_fifo_cnt = 0;
reg [31:0] din_fifo_cnt = 0;
 
// temp debugging
reg [63:0] v_counter = 0;
reg [63:0] ie_counter = 0;
reg [63:0] pr_counter = 0;
reg [63:0] v_zero = 0;
reg [63:0] ie_zero = 0;

reg rst_called = 0;

always @(posedge clk) begin
	sr_resp_valid <= softreg_req_valid && !softreg_req_isWrite;
	if (softreg_req_valid && !softreg_req_isWrite) begin
		case (softreg_req_addr)
			 32'h00: sr_resp_data <= n_vertices;
			 32'h08: sr_resp_data <= n_inedges;
			 32'h10: sr_resp_data <= v_vcount;
			 32'h18: sr_resp_data <= softreg_req_addr;
			 32'h20: sr_resp_data <= pr_state;
			 32'h28: sr_resp_data <= vert_to_fetch;
			 32'h30: sr_resp_data <= ie_to_fetch;
			 32'h38: sr_resp_data <= total_runs;
			 32'h40: sr_resp_data <= round;
			 32'h48: sr_resp_data <= pr_pending;
			 32'h50: sr_resp_data <= din;
			 32'h58: sr_resp_data <= rvalid_m ? rid_m : 666;
			 32'h60: sr_resp_data <= arready_m;
			 32'h68: sr_resp_data <= arvalid_m;
			 32'h70: sr_resp_data <= arid_m;
			 32'h78: sr_resp_data <= v_oready;  
			 32'h80: sr_resp_data <= ie_oready;
			 32'h88: sr_resp_data <= init_val;
			 32'h90: sr_resp_data <= init_div_over;
			 32'h98: sr_resp_data <= vfirst;
			 32'ha0: sr_resp_data <= vert_fifo_empty;
			 32'ha8: sr_resp_data <= inedge_fifo_empty;
			 32'hb0: sr_resp_data <= vert_fifo_rdreq;
			 32'hb8: sr_resp_data <= ie_getpr;
			 32'hc0: sr_resp_data <= v_counter;
			 32'hc8: sr_resp_data <= v_zero;  
			 32'hd0: sr_resp_data <= ie_counter;
			 32'hd8: sr_resp_data <= ie_zero;
			 32'he0: sr_resp_data <= pr_counter;
			 32'he8: sr_resp_data <= ie_addr;  
			 32'hf0: sr_resp_data <= v_addr;  
			 32'hf8: sr_resp_data <= wb_vcount;  
			 32'h100: sr_resp_data <= vready;  
			 32'h108: sr_resp_data <= vdone;  
			 32'h110: sr_resp_data <= ie_offset;  
			 32'h118: sr_resp_data <= n_ie_left;  
			 32'h120: sr_resp_data <= dividend;  
			 32'h128: sr_resp_data <= divisor;  
			 32'h130: sr_resp_data <= pr_waddr;  
			 32'h138: sr_resp_data <= wbready;  
			 32'h140: sr_resp_data <= last_quotient;  
			 32'h148: sr_resp_data <= v_bounds;
			 32'h150: sr_resp_data <= div_fifo_empty;  
			 32'h158: sr_resp_data <= din_fifo_empty;  
			 32'h160: sr_resp_data <= pr_fifo_empty;  
			 32'h168: sr_resp_data <= init_din;  
			 32'h170: sr_resp_data <= next_run;  
			 32'h178: sr_resp_data <= count;  
			 32'h180: sr_resp_data <= READ_VERT;
			 32'h188: sr_resp_data <= ie_batch;  
			 32'h190: sr_resp_data <= ie_bounds;  
			 32'h198: sr_resp_data <= ie_base;  
			 32'h1a0: sr_resp_data <= 555;  
			 32'h1a8: sr_resp_data <= INT_W;  
			 32'h1b0: sr_resp_data <= pr_sum;  
			default: sr_resp_data <= 0;
		endcase
	end
end

/* data read logic to read in some # vertices -> some # in-edge vertices -> random PR reads
currently round-robin between read types, but if streaming buffers are full,
will keep performing random reads
*/
// TODO add rst

always @(posedge clk) begin

	case(pr_state)
		// wait for start of each round
		WAIT: begin
			v_addr <= v_base_addr;
			vert_to_fetch <= n_vertices;
			v_base <= 8'd0;
			v_bounds <= 8'd8; // TODO handle < 4 for total vertices (not critical)                    

			ie_addr <= ie_base_addr;
			ie_to_fetch <= n_inedges;
			// TODO issues with Buffer 1-cycle latency when reading multiple rounds
			// can use more batches when Buffer can accept adjacent reads
			ie_batch <= 4'd1;
			ie_base <= ie_base_addr[5:3];
			ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch : 512/INT_W;

			if (round == 0) begin
				if ((softreg_req_valid && softreg_req_isWrite && (softreg_req_addr == `DONE_READ_PARAMS))
						|| next_run) begin

					// for debugging
					$display("n_vertices: %0d", n_vertices);
					$display("n_inedges: %0d", n_inedges);
					$display("total_rounds: %0d", total_rounds-1);
					$display("pr_raddr: 0x%x", base_pr_raddr);
					$display("pr_waddr: 0x%x", base_pr_waddr);
					$display("dividend = %0b, divisor = %0b", (1 << PREC), n_vertices);

					init_din <= 1;
					round <= 1;
					total_runs <= total_runs - 1;
					next_run <= 0;
				end
			end
			else begin
				if (round == total_rounds+1) begin
                	if (total_runs == 0) begin
						$display("Cycle Counts:");
						//$display("Read vert: %0d", count0);
						//$display("Read ie vert: %0d", count1);
						//$display("Read prs: %0d", count2);
						$display("Total cycles: %0d", count);
						$display("--------------------------------");
						$display("v_oready_cnt = %0d", v_oready_cnt);
						$display("ie_oready_cnt = %0d", ie_oready_cnt);
						$display("pr_fifo_cnt = %0d", pr_fifo_cnt);
						$display("din_fifo_cnt = %0d", din_fifo_cnt);
						$display("Done.");
					end
					else begin
						// start another run on n rounds
						total_runs <= total_runs - 1;
						round <= 0;
						next_run <= 1;
						$display("-------- Starting Next Run ---------");
					end
				end
				// first round
				else if (round == 1) begin
					init_din <= 0;
					// wait for initial division to complete
					if (dout) begin
						init_val <= quotient;
						$display("init_val: %0b, %0d", quotient, quotient);
						pr_state <= READ_VERT;
						round <= round + 1;
						init_div_over <= 1;
						/* $display("\n*** Round 1: quotient is %b, remainder %b ***\n", */ 
												/* quotient, remainder); */
					end
				end
				// all other rounds
				else begin
					pr_state <= READ_VERT;
					round <= round + 1;
					$display("\n*** Starting Round: %0d ***", round-1);
				end
			end
		end
		READ_VERT: begin
			// read in up to 4 (n_in_edge,n_out_edge) pairs in one read
			if (arready_m && arvalid_m) begin
				v_addr <= v_addr + 64;
				v_base <= 0;
				v_bounds <= vert_to_fetch < 512/(INT_W*2) ? vert_to_fetch[7:0] : 512/(INT_W*2);

				v_counter <= v_counter + 1;

				if (vert_to_fetch <= 512/(INT_W*2))	begin
					vert_to_fetch <= 0;
					v_zero <= 1;
				end
				else vert_to_fetch <= vert_to_fetch - 512/(INT_W*2);

				pr_state <= READ_INEDGES;
			end  
			else if (!arvalid_m)
				pr_state <= READ_INEDGES;
		end
		READ_INEDGES: begin
			if (arready_m && arvalid_m) begin
				ie_addr <= ie_addr[5:3] == 0 ? ie_addr+64 
						 	: ie_addr+64-(ie_addr[5:3] << 3);
				ie_base <= ie_addr[5:3];
				ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch[7:0] : 512/INT_W;

				ie_counter <= ie_counter + 1;

				if (ie_to_fetch <= 512/INT_W) begin
					ie_to_fetch <= 0;
					ie_zero <= 1;
				end
				else 
					ie_to_fetch <= ie_to_fetch - 512/INT_W + ie_addr[5:3];

				/* ie_batch <= ie_batch - 1; */

				pr_state <= READ_PR;
			end
			else if (!arvalid_m)
				pr_state <= READ_PR;
		end
		READ_PR: begin
			if (wait_priority)
				pr_state <= WAIT;
			else if (vert_fifo_empty)
				pr_state <= READ_VERT;
			else if (inedge_fifo_empty)
				pr_state <= READ_INEDGES;
			else if ((arready_m && arvalid_m) || !arvalid_m) begin
				pr_state <= CONTROL;
				if (arready_m && arvalid_m)
					pr_counter <= pr_counter + 1;
			end
		end
		CONTROL: begin
			if ((vert_to_fetch > 0) && !v_oready)
				pr_state <= READ_VERT;
			else if ((ie_to_fetch > 0) && !ie_oready)
				pr_state <= READ_INEDGES;
			else
				pr_state <= READ_PR;
		end
	endcase

	if (rst) begin
		rst_called <= 1;
		pr_state <= WAIT;
	end
end

// debug signals
always @(posedge clk) begin
	if (v_oready && !vert_fifo_full) v_oready_cnt <= v_oready_cnt + 1;
	if (ie_oready && !inedge_fifo_full) ie_oready_cnt <= ie_oready_cnt + 1;
	if (pr_fifo_wrreq && !pr_fifo_full) pr_fifo_cnt <= pr_fifo_cnt + 1;
	if (din_fifo_wrreq && !din_fifo_full) din_fifo_cnt <= din_fifo_cnt + 1;
end

// FIFO for vertex in-edges offset + # out-edges stored as a pair
HullFIFO #(
	.TYPE(0),
	.WIDTH(128),
	.LOG_DEPTH(6) // buffer 64 vertices at once
) vertex_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(vert_fifo_wrreq),
	.data(vert_fifo_in),
	.full(vert_fifo_full),
	.rdreq(vert_fifo_rdreq),
	.q(vert_fifo_out),
	.empty(vert_fifo_empty)
);

// FIFO for in-edges
HullFIFO #(
	.TYPE(0),
	.WIDTH(64),
 	// buffer 64 vertices at once
	.LOG_DEPTH(6)
) inedge_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(inedge_fifo_wrreq),
	.data(inedge_fifo_in),
	.full(inedge_fifo_full),
	.rdreq(inedge_fifo_rdreq),
	.q(inedge_fifo_out),
	.empty(inedge_fifo_empty)
);

// FIFO for dividend+divisor
HullFIFO #(
	.TYPE(0),
	.WIDTH(128),
	.LOG_DEPTH(6)
) din_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(din_fifo_wrreq),
	.data(din_fifo_in),
	.full(din_fifo_full),
	.rdreq(din_fifo_rdreq),
	.q(din_fifo_out),
	.empty(din_fifo_empty)
);
      
// FIFO for division results
HullFIFO #(
	.TYPE(0),
	.WIDTH(64),
	.LOG_DEPTH(6)
) div_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(div_fifo_wrreq),
	.data(div_fifo_in),
	.full(div_fifo_full),
	.rdreq(div_fifo_rdreq),
	.q(div_fifo_out),
	.empty(div_fifo_empty)
);
 
// FIFO for random old PR requests
HullFIFO #(
	.TYPE(0),
	.WIDTH(64),
	.LOG_DEPTH(6)
) pr_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(pr_fifo_wrreq),
	.data(pr_fifo_in),
	.full(pr_fifo_full),
	.rdreq(pr_fifo_rdreq),
	.q(pr_fifo_out),
	.empty(pr_fifo_empty)
);
  
AddrParser #(
	.FULL_WIDTH(512),
	.WIDTH(64)
) parser (
	pr_rready,
	pr_raddr[5:3],
	pr_rdata,
	pr_odata
);

reg [31:0] get_vert_cnt = 0;

// VERT: read 2 things to get # i-e, store both # oe, wait for PR reads
always @(posedge clk) begin
	case(vready)
		WAIT_VERT: begin
			if (pr_state == WAIT) begin
				if (round < 2)
					if (init_div_over)
						vready <= GET_VERT;
				else begin
					vready <= GET_VERT;
					pr_sum <= 0;
				end
			end
		end
		// read vertex to process, it's starting offset
		GET_VERT: begin
			// TODO signal idea: last n_ie_left
			vdone <= 0;
			get_vert_cnt <= get_vert_cnt + 1;
			if (!vert_fifo_empty || (v_vcount == n_vertices-1)) begin
				// handle first vertex
				if (v_vcount == 0) begin
					if (vfirst) begin
						n_outedge0 <= vert_fifo_out[INT_W-1:0];
						vfirst <= 0;
					end
					else begin
						n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W];
						ie_offset <= vert_fifo_out[INT_W*2-1:INT_W];
						n_outedge1 <= vert_fifo_out[INT_W-1:0];
						vready <= GET_SUM;
					end
				end
				else begin
					n_outedge0 <= n_outedge1;
					n_outedge1 <= vert_fifo_out[INT_W-1:0];

					// handle last vertex
					if (v_vcount == n_vertices-1)
						n_ie_left <= n_inedges - ie_offset;
					else
						n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W] - ie_offset;

					ie_offset <= vert_fifo_out[INT_W*2-1:INT_W];
					vready <= GET_SUM;
				end
			end
		end
		GET_SUM: begin
			if (n_ie_left > 0) begin
				// fetch PR of current in-edge vertex, add it to running sum
 				if (round == 2 | !pr_fifo_empty) begin
					/* $display("\tIE -- %0d", n_ie_left); */
					if (round == 2)
						pr_sum <= pr_sum + init_val;
					else
						pr_sum <= pr_sum + pr_fifo_out;
					n_ie_left <= n_ie_left - 1;
				end
			end
			else begin
				/* $display("VERTEX %0d", v_vcount); */
				// put sum into divider, when divider is done it writes back
				vdone <= 1;
				// start processing next vertex
				vready <= GET_VERT;

				if (v_vcount+1 == n_vertices)
					v_vcount <= 0;
				else
					v_vcount <= v_vcount + 1;
			end
		end
	endcase

	// we've processed all vertices, reset what we need to
	if (wb_vcount + 1 == n_vertices)
		vfirst <= 1;
end

// INEDGES: read old PR, feed into results queue for VERT stage
always @(posedge clk) begin
	if (!pr_pending && !inedge_fifo_empty && !pr_fifo_full) begin
		pr_raddr <= base_pr_raddr + (inedge_fifo_out << 3);
   		pr_pending <= 1;
	end
	else if (arready_m && arvalid_m && (arid_m == 2))
		pr_pending <= 0;
end

// DIV: receive #oe and pr sum, divide, put into wb fifo
always @(posedge clk) begin
	if (!din_fifo_empty && !div_fifo_full) begin
		din <= 1;
		dividend <= din_fifo_out[INT_W*2-1:INT_W];
		divisor <= din_fifo_out[INT_W-1:0];
		/* $display("dividing %0b / %0b", din_fifo_out[INT_W*2-1:INT_W], din_fifo_out[INT_W-1:0]); */
	end
	else din <= 0;

	// inputs for computing the initial PR value
	if ((round == 0) && softreg_req_valid && softreg_req_isWrite) begin
		if (softreg_req_addr == `DONE_READ_PARAMS) begin
			dividend <= 1 << PREC;
			divisor <= n_vertices;
		end
	end
end

/* reg print_done = 0; */
/* reg reads_done = 0; */
/* reg [511:0] line0 = 0; */

// for debug
/* always @(posedge clk) begin */
/* 	if (!reads_done &&!print_done && wb_vcount + 1 == n_vertices) begin */
/* 		if (rid_m == 3 && rvalid_m) begin */
/* 			line0 <= rdata_m; */
/* 			/1* $display("line: %0b", rdata_m); *1/ */
/* 			reads_done <= 1; */
/* 		end */
/* 	end */
/* end */

/* genvar p; */
/* generate */
/* 	for (p=0; p<8; p = p+1) begin */
/* 		always @(posedge clk) begin */
/* 			if (reads_done && !print_done && wb_vcount + 1 == n_vertices) begin */
/* 				$display("PR %0d = %0b", p+2, line0[511-p*64-1:448-64*p]); */
/* 				print_done <= 1; */
/* 				reads_done <= 0; */
/* 			end */
/* 		end */
/* 	end */
	/* for (p=0; p<2; p = p+1) begin */
	/* 	always @(posedge clk) begin */
	/* 		if (reads_done && !print_done && wb_vcount + 1 == n_vertices) begin */
	/* 			$display("PR %0d = %0b", p+8, line1[511-p*64-1:448-64*p]); */
	/* 			print_done <= 1; */
	/* 		end */
	/* 	end */
	/* end */
/* endgenerate */

// WB: receive from DIV and WB fifo, writeback new PR
always @(posedge clk) begin
	if (wbready && !div_fifo_empty) begin
		wbready <= 0;
		// wvalue = div_fifo_out
		pr_waddr <= base_pr_waddr + (wb_vcount << 3);
		pr_awvalid <= 1;
		pagerank <= div_fifo_out;
	end

	if (pr_awvalid) pr_awvalid <= 0;

	if (!wbready && wvalid_m && wready_m) begin
		/* $display("--------- WRITING %0b to 0x%0h ---------", */
		/* 	   		pagerank, pr_waddr); */
		wbready <= 1;

		if (wb_vcount + 1 == n_vertices) begin
			$display("*** Done with round %0d of PR ***", round-2);
			base_pr_waddr <= base_pr_raddr;
			base_pr_raddr <= base_pr_waddr;
			wb_vcount <= 0;
			wait_priority <= 1;
		end
		else wb_vcount <= wb_vcount + 1;
	end
 
		// for debug
		/* if (wb_vcount + 1 == n_vertices) begin */
		/* 	if (print_done) begin */
		/* 		print_done <= 0; */
		/* 		$display("*** Done with round %0d of PR ***", round-2); */
		/* 		base_pr_waddr <= base_pr_raddr; */
		/* 		base_pr_raddr <= base_pr_waddr; */
		/* 		wb_vcount <= 0; */
		/* 		wait_priority <= 1; */
		/* 	end */
		/* end */ 

	if (pr_state == WAIT)
		wait_priority <= 0;

	// parameter initialization; need here because modifies base_pr addresses
	if (softreg_req_valid && softreg_req_isWrite) begin
		case(softreg_req_addr)
			`N_VERT: n_vertices <= softreg_req_data;
			`N_INEDGES: n_inedges <= softreg_req_data;
			`VADDR: v_base_addr <= softreg_req_data;
			`IEADDR: ie_base_addr <= softreg_req_data;
			`WRITE_ADDR0: base_pr_raddr <= softreg_req_data;
			`WRITE_ADDR1: base_pr_waddr <= softreg_req_data;
			`N_ROUNDS: total_rounds <= softreg_req_data + 1; // add 1 for init stage
		endcase
	end
end

endmodule
