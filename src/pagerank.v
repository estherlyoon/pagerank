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
// log depth of FIFOs
localparam FIFO_DEPTH = 6; 

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

// tmp debug
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

// tmp debug
reg [31:0] inbuffer_cnt = 0;
reg [31:0] outbuffer_cnt = 0;
reg [31:0] txn_cnt = 0;
     
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
	v_odata // fed into FIFO
);

// tmp debug
reg [31:0] vert_read_cnt0 = 0;
reg [31:0] vert_read_cnt = 0;
reg [31:0] div_read_cnt = 0;
reg [31:0] din_read_cnt = 0;
reg [31:0] ie_wcnt = 0;
reg [31:0] pr_wcnt = 0;
reg [31:0] din_wcnt = 0;
reg [31:0] div_wcnt = 0;
reg [31:0] vdone_cnt = 0;
reg [31:0] div_fifo_cnt = 0;
reg [31:0] get_vert_cnt0 = 0;
reg [31:0] get_vert_cnt1 = 0;
reg [31:0] get_vert_cnt2 = 0;
reg [31:0] get_vert_cnt3 = 0;
reg [31:0] get_vert_cnt4 = 0;
reg [31:0] get_sum_cnt = 0;
reg [31:0] get_sum_cnt0 = 0;
reg [31:0] get_sum_cnt1 = 0;
reg [31:0] dout_cnt = 0;
reg [31:0] outedge_sum = 0;
reg [31:0] edgecnt_sum = 0;
reg [63:0] oe_mem [99:0];
reg [63:0] offset_mem [99:0];
reg [511:0] axi_mem [24:0];
reg [64:0] axi_words [7:0];
reg [63:0] axi_idx_rq = 0;
reg [63:0] axi_word_rq = 0;
reg [63:0] host_idx = 0;


always @(posedge clk) begin
	if (dout && init_div_over)
		dout_cnt <= dout_cnt + 1;
end

genvar w;
generate
for (w = 0; w < 4; w = w + 1) begin
	// remember idx is opposite
	always @(*) begin
		axi_words[w] = axi_mem[axi_idx_rq][(w+1)*64-1:w*64];
	end
end
endgenerate
 

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
reg vert_fifo_init = 0;
wire vert_fifo_not_empty = !vert_fifo_empty && vert_fifo_init;
 
// in-edge vertices FIFO signals
reg inedge_fifo_wrreq;
reg [63:0] inedge_fifo_in;
wire inedge_fifo_full;
wire inedge_fifo_rdreq;
wire [63:0] inedge_fifo_out;
wire inedge_fifo_empty;  
reg inedge_fifo_init = 0;
wire inedge_fifo_not_empty = !inedge_fifo_empty && inedge_fifo_init;

// PR data FIFO signals
reg pr_fifo_wrreq;
reg [63:0] pr_fifo_in;
wire pr_fifo_full;
wire pr_fifo_rdreq;
wire [63:0] pr_fifo_out;
wire pr_fifo_empty;
reg pr_fifo_init = 0;
wire pr_fifo_not_empty = !pr_fifo_empty && pr_fifo_init;

// divisor+dividend FIFO signals
reg din_fifo_wrreq;
reg [127:0] din_fifo_in;
wire din_fifo_full;
wire din_fifo_rdreq;
wire [127:0] din_fifo_out;
wire din_fifo_empty;
reg din_fifo_init = 0;
wire din_fifo_not_empty = !din_fifo_empty && din_fifo_init;
 
// div results FIFO signals
reg div_fifo_wrreq;
reg [63:0] div_fifo_in;
wire div_fifo_full;
wire div_fifo_rdreq;
wire [63:0] div_fifo_out;
wire div_fifo_empty;
reg div_fifo_init = 0;
wire div_fifo_not_empty = !div_fifo_empty && div_fifo_init;

always @(posedge clk) begin
	if (vert_fifo_wrreq) vert_fifo_init <= 1;
	if (inedge_fifo_wrreq) inedge_fifo_init <= 1;
	if (pr_fifo_wrreq) pr_fifo_init <= 1;
	if (din_fifo_wrreq) din_fifo_init <= 1;
	if (div_fifo_wrreq) div_fifo_init <= 1;
end

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
reg pr_wvalid = 0;
reg pr_awvalid = 0;
reg wb_pending = 0;
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
     
reg [31:0] div_pending = 0;
reg [31:0] div_fifo_slots = 0;

// keep track for making rdreqs from din_fifo -> divider
always @(posedge clk) begin
	if (init_div_over) begin
		if (dvalid && !dout)
			div_pending <= div_pending + 1;
		else if (dout && !dvalid)
			div_pending <= div_pending - 1;
	end

	if (div_fifo_wrreq && !div_fifo_full && div_fifo_rdreq && div_fifo_not_empty) begin
	end
	else if (div_fifo_wrreq && !div_fifo_full)
		div_fifo_slots <= div_fifo_slots + 1;
	// does this fix bug when fifo gets read from even if never written to?
	else if (div_fifo_rdreq && div_fifo_not_empty)
		div_fifo_slots <= div_fifo_slots - 1;
end
 
// set when something read to buffers
reg v_pending = 0;
reg ie_pending = 0;

// set when pr address set
reg pr_pending = 0;

always @(posedge clk) begin
	if (v_odata_req && v_oready)
		outbuffer_cnt <= outbuffer_cnt + 1;
	if (vert_fifo_rdreq && !vert_fifo_empty)
		vert_read_cnt0 <= vert_read_cnt0 + 1;
	if (vert_fifo_rdreq && vert_fifo_not_empty)
		vert_read_cnt <= vert_read_cnt + 1;
	if (din_fifo_rdreq && din_fifo_not_empty)
		din_read_cnt <= din_read_cnt + 1;
	if (div_fifo_rdreq && div_fifo_not_empty)
		div_read_cnt <= div_read_cnt + 1;
end
 
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
	inedge_fifo_wrreq = ie_oready && !inedge_fifo_full;
	inedge_fifo_in = ie_odata;

	pr_rready = rvalid_m && (rid_m == 2);
	pr_rdata = rdata_m;
	// this is fine because we only request a read when fifo !full
	pr_fifo_wrreq = pr_rready;
	pr_fifo_in = pr_odata;

    din_fifo_wrreq = vdone && !din_fifo_full;
	din_fifo_in =  { pr_dividend, n_outedge0 }; 

	div_fifo_wrreq = dout && init_div_over;
	div_fifo_in = quotient;

	// logic to feed into divisor
	if (init_din) begin
		dividend = 1 << PREC;
		divisor = n_vertices;
	end
	else begin
		din = din_fifo_rdreq && din_fifo_not_empty;
		dividend = din_fifo_out[INT_W*2-1:INT_W];
		divisor = din_fifo_out[INT_W-1:0];
	end

	// tmp debug
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
			arvalid_m = !v_pending && !v_oready && (vert_to_fetch > 0);
		end
		READ_INEDGES: begin
			arid_m = 1;
			araddr_m = ie_addr;
			arlen_m = 0;
			arvalid_m = (round > 2) && !ie_pending && !ie_oready && (ie_to_fetch > 0)
						&& (ie_batch > 0) && !inedge_fifo_full;
		end
		READ_PR: begin
			arid_m = 2;
			araddr_m = pr_raddr;
			arlen_m = 0;
			arvalid_m = !pr_fifo_full && inedge_fifo_not_empty && pr_pending; // TODO can remove first two?
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
reg [1:0] vready = VERT_INIT;
reg [1:0] vfirst = 1;

// in-edge stage signals
wire ie_getpr = arvalid_m && arready_m && (arid_m == 2);

localparam VERT_INIT = 0;
localparam GET_VERT = 1;
localparam GET_SUM = 2;

// writing back signals
localparam TRANSACTION = 0;
localparam WRITE_DONE = 1;
reg wb_state = TRANSACTION;

assign vert_fifo_rdreq = vready == GET_VERT && (!vfirst || (v_vcount == 0));
assign inedge_fifo_rdreq = ie_getpr && round > 2;
assign pr_fifo_rdreq = (vready == GET_SUM) && (n_ie_left > 0) && (round > 2);
assign din_fifo_rdreq = !div_fifo_full && ((1 << FIFO_DEPTH) > (div_pending + div_fifo_slots));
assign div_fifo_rdreq = !wb_pending && div_fifo_not_empty;

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
reg [31:0] get_vert_cnt = 0;

always @(posedge clk) begin
	sr_resp_valid <= softreg_req_valid && !softreg_req_isWrite;
	if (softreg_req_valid && !softreg_req_isWrite) begin
		case (softreg_req_addr)
			 32'h00: sr_resp_data <= div_fifo_cnt;
			 32'h08: sr_resp_data <= pr_wcnt;
			 32'h10: sr_resp_data <= v_vcount;
			 32'h18: sr_resp_data <= softreg_req_addr;
			 32'h20: sr_resp_data <= pr_state;
			 32'h28: sr_resp_data <= vert_to_fetch;
			 32'h30: sr_resp_data <= ie_to_fetch;
			 32'h38: sr_resp_data <= total_runs;
			 32'h40: sr_resp_data <= round;
			 32'h48: sr_resp_data <= pr_pending;
			 32'h50: sr_resp_data <= din;
			 32'h58: sr_resp_data <= 0;
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
			 32'h138: sr_resp_data <= wb_pending;
			 32'h140: sr_resp_data <= last_quotient;
			 32'h148: sr_resp_data <= v_bounds;
			 32'h150: sr_resp_data <= div_fifo_empty;
			 32'h158: sr_resp_data <= din_fifo_empty;
			 32'h160: sr_resp_data <= pr_fifo_empty;
			 32'h168: sr_resp_data <= init_din;
			 32'h170: sr_resp_data <= 0;
			 32'h178: sr_resp_data <= count;
			 32'h180: sr_resp_data <= edgecnt_sum; // ie_left cnt summed
			 32'h188: sr_resp_data <= 0;
			 32'h190: sr_resp_data <= ie_bounds;
			 32'h198: sr_resp_data <= ie_base;
			 32'h1a0: sr_resp_data <= get_vert_cnt;
			 32'h1a8: sr_resp_data <= outedge_sum; // n outedges cnt summed
			 32'h1b0: sr_resp_data <= pr_sum;
			 32'h1b8: sr_resp_data <= v_oready_cnt;
			 32'h1c0: sr_resp_data <= ie_oready_cnt;
			 32'h1c8: sr_resp_data <= pr_fifo_cnt;
			 32'h1d0: sr_resp_data <= dout_cnt;
			 32'h1d8: sr_resp_data <= din_fifo_cnt;
			 32'h1e0: sr_resp_data <= outbuffer_cnt;
			 32'h1e8: sr_resp_data <= div_read_cnt;
			 32'h1f0: sr_resp_data <= din_read_cnt;
			 32'h1f8: sr_resp_data <= div_fifo_cnt;
			 32'h200: sr_resp_data <= pr_wcnt;
			 32'h208: sr_resp_data <= din_wcnt;
			 32'h210: sr_resp_data <= div_wcnt;
			 32'h218: sr_resp_data <= ie_wcnt;
			 32'h220: sr_resp_data <= din_fifo_full;
			 32'h228: sr_resp_data <= div_fifo_full;
			 32'h230: sr_resp_data <= pr_fifo_full;
			 32'h238: sr_resp_data <= vdone_cnt;
			 32'h240: sr_resp_data <= txn_cnt;
			 32'h248: sr_resp_data <= v_pending;
			 32'h250: sr_resp_data <= ie_pending;
			 32'h258: sr_resp_data <= get_vert_cnt0;
			 32'h260: sr_resp_data <= get_vert_cnt1;
			 32'h268: sr_resp_data <= get_vert_cnt2;
			 32'h270: sr_resp_data <= get_vert_cnt3;
			 32'h278: sr_resp_data <= get_sum_cnt;
			 32'h280: sr_resp_data <= get_sum_cnt0;
			 32'h288: sr_resp_data <= get_sum_cnt1;
			 32'h290: sr_resp_data <= get_vert_cnt4;
			 32'h298: sr_resp_data <= div_fifo_slots;
			 32'h2a0: sr_resp_data <= div_pending;
			 32'h2a8: sr_resp_data <= oe_mem[host_idx];
			 32'h2b0: sr_resp_data <= offset_mem[host_idx];
			 32'h2b8: sr_resp_data <= axi_words[axi_word_rq];
			 32'h2c0: sr_resp_data <= host_idx;
			 32'h2c8: sr_resp_data <= axi_idx_rq;
			 32'h2d0: sr_resp_data <= axi_word_rq;
			 32'h2d8: sr_resp_data <= vert_read_cnt;
			 32'h2e0: sr_resp_data <= vert_read_cnt0;
			default: sr_resp_data <= 0;
		endcase
	end
end

/* data read logic to read in some # vertices -> some # in-edge vertices -> random PR reads
currently round-robin between read types, but if streaming buffers are full,
will keep performing random reads
*/
// TODO add rst

reg [32:0] axi_idx = 0;

always @(posedge clk) begin

	if (v_rready) begin
		v_pending <= 0;
		if (round == 2 && axi_idx < 25) begin
			axi_mem[axi_idx] <= rdata_m;
			axi_idx <= axi_idx + 1;
		end
	end
	if (ie_rready)
		ie_pending <= 0;

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
						$display("get_vert_cnt = %0d", get_vert_cnt);
						$display("v_vcount = %0d\n", v_vcount);
						$display("div_read_cnt = %0d", div_read_cnt);
						$display("din_read_cnt = %0d", din_read_cnt);
						$display();
						$display("din_fifo_cnt = %0d", din_fifo_cnt);
						$display("div_fifo_cnt = %0d", div_fifo_cnt);
						$display("pr_fifo_cnt = %0d", pr_fifo_cnt);
						$display("ie_wcnt = %0d", ie_wcnt);
						$display("din_wcnt = %0d", din_wcnt);
						$display("div_wcnt = %0d", div_wcnt);
						$display("pr_wcnt = %0d", pr_wcnt);
						$display("vdone_cnt = %0d", vdone_cnt);
						$display("Done.");
						$finish();
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
				v_pending <= 1;

				// tmp debugging
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
				ie_pending <= 1;

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
	if (div_fifo_wrreq && !div_fifo_full) div_fifo_cnt <= div_fifo_cnt + 1;
	if (inedge_fifo_wrreq) ie_wcnt <= ie_wcnt + 1;
	if (pr_fifo_wrreq) pr_wcnt <= pr_wcnt + 1;
	if (din_fifo_wrreq) din_wcnt <= din_wcnt + 1;
	if (div_fifo_wrreq) div_wcnt <= div_wcnt + 1;
	if (vdone) vdone_cnt <= vdone_cnt + 1;
end

// FIFO for vertex in-edges offset + # out-edges stored as a pair
HullFIFO #(
	.TYPE(0),
	.WIDTH(128),
	.LOG_DEPTH(FIFO_DEPTH) // buffer 64 vertices at once
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
	.LOG_DEPTH(FIFO_DEPTH)
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
	.LOG_DEPTH(FIFO_DEPTH)
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
	.LOG_DEPTH(FIFO_DEPTH)
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
	.LOG_DEPTH(FIFO_DEPTH)
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

reg [63:0] vmem_idx = 0;

// VERT: read 2 things to get # i-e, store both # oe, wait for PR reads
always @(posedge clk) begin
	case(vready)
		VERT_INIT: begin
			if (softreg_req_valid && softreg_req_isWrite && (softreg_req_addr == `DONE_READ_PARAMS))
				vready <= GET_VERT;
		end
		// read vertex to process, it's starting offset
		GET_VERT: begin
			vdone <= 0;
			get_vert_cnt0 <= get_vert_cnt0 + 1;
			if (!vert_fifo_empty || (v_vcount == n_vertices-1)) begin
				get_vert_cnt1 <= get_vert_cnt1 + 1;
				// handle first vertex
				if (v_vcount == 0) begin
					get_vert_cnt <= get_vert_cnt + 1;
					get_vert_cnt2 <= get_vert_cnt2 + 1;
					if (vfirst) begin
						n_outedge0 <= vert_fifo_out[INT_W-1:0];
						vfirst <= 0;

						get_vert_cnt4 <= get_vert_cnt4 + 1;
						offset_mem[0] <= vert_fifo_out[INT_W*2-1:INT_W];
						oe_mem[0] <= vert_fifo_out[INT_W-1:0];
						outedge_sum <= outedge_sum + vert_fifo_out[INT_W-1:0];
						vmem_idx <= vmem_idx + 1;
					end
					else begin
						n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W];
						ie_offset <= vert_fifo_out[INT_W*2-1:INT_W];
						n_outedge1 <= vert_fifo_out[INT_W-1:0];
						vready <= GET_SUM;

						// debug
						edgecnt_sum <= edgecnt_sum + vert_fifo_out[INT_W*2-1:INT_W]; 
						outedge_sum <= outedge_sum + vert_fifo_out[INT_W-1:0]; 
						if (vmem_idx < 100) begin
							oe_mem[vmem_idx] <= vert_fifo_out[INT_W-1:0];  
							offset_mem[vmem_idx] <= vert_fifo_out[INT_W*2-1:INT_W]; 
						end
						vmem_idx <= vmem_idx + 1;
					end
				end
				else begin
					n_outedge0 <= n_outedge1;
					n_outedge1 <= vert_fifo_out[INT_W-1:0];

					// debug
					outedge_sum <= outedge_sum + vert_fifo_out[INT_W-1:0]; 
					get_vert_cnt3 <= get_vert_cnt3 + 1;
					if (vmem_idx < 100) begin
						oe_mem[vmem_idx] <= vert_fifo_out[INT_W-1:0];  
						offset_mem[vmem_idx] <= vert_fifo_out[INT_W*2-1:INT_W];  
					end
					vmem_idx <= vmem_idx + 1;
					
					// handle last vertex
					if (v_vcount == n_vertices-1) begin
						n_ie_left <= n_inedges - ie_offset;
						edgecnt_sum <= edgecnt_sum + n_inedges - ie_offset;
					end
					else begin
						get_vert_cnt <= get_vert_cnt + 1;
						n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W] - ie_offset;
						ie_offset <= vert_fifo_out[INT_W*2-1:INT_W];
						edgecnt_sum <= edgecnt_sum + vert_fifo_out[INT_W*2-1:INT_W] - ie_offset;
					end

					vready <= GET_SUM;
				end
			end
		end
		GET_SUM: begin
			get_sum_cnt <= get_sum_cnt + 1;
			if (n_ie_left > 0) begin
				get_sum_cnt0 <= get_sum_cnt0 + 1;
				// fetch PR of current in-edge vertex, add it to running sum
 				if (round == 2 || pr_fifo_not_empty) begin
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
				get_sum_cnt1 <= get_sum_cnt1 + 1;
				// start processing next vertex
				if (!din_fifo_full) begin
					vdone <= 1;
					vready <= GET_VERT;
					pr_sum <= 0;
					if (v_vcount + 1 == n_vertices)
						v_vcount <= 0;
					else
						v_vcount <= v_vcount + 1;
				end

			end
		end
	endcase

	// we've processed all vertices, reset what we need to
	if (wb_vcount + 1 == n_vertices)
		vfirst <= 1;
end

// INEDGES: read old PR, feed into results queue for VERT stage
always @(posedge clk) begin
	// conditions for reading: not on init round, not handling another
	// request, FIFOs are in the right state (src is not empty, dest is not
	// full)
	// shouldn't really need round > 2 because ie_fifo should be empty at
	// start
	if (round > 2 && !pr_pending && inedge_fifo_not_empty && !pr_fifo_full) begin
		pr_raddr <= base_pr_raddr + (inedge_fifo_out << 3);
   		pr_pending <= 1;
	end
	else if (arready_m && arvalid_m && (arid_m == 2))
		pr_pending <= 0;
end

// WB: receive from DIV and WB fifo, writeback new PR
// invariant: only write back one result at a time (wb_pending = 1)
always @(posedge clk) begin

	if (!wb_pending && div_fifo_not_empty) begin
		wb_pending <= 1;
		pagerank <= div_fifo_out;

		pr_waddr <= base_pr_waddr + (wb_vcount << 3);
		pr_awvalid <= 1;
		pr_wvalid <= 1;

		// tmp debugging
		txn_cnt <= txn_cnt + 1;
	end

	if (awvalid_m && awready_m)
 		pr_awvalid <= 0;

	if (wvalid_m && wready_m)
 		pr_wvalid <= 0;

	if (bvalid_m) begin
		/* $display("--------- WRITING %0b to 0x%0h ---------", */
		/* 	   		pagerank, pr_waddr); */
		wb_pending <= 0;
		if (wb_vcount + 1 == n_vertices) begin
			$display("*** Done with round %0d of PR ***", round-2);
			base_pr_waddr <= base_pr_raddr;
			base_pr_raddr <= base_pr_waddr;
			wb_vcount <= 0;
			wait_priority <= 1;
		end
		else wb_vcount <= wb_vcount + 1;
	end
 
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
			 32'h50: host_idx <= softreg_req_data;
			 32'h58: axi_idx_rq <= softreg_req_data;
			 32'h60: axi_word_rq <= softreg_req_data;
		endcase
	end
end
 
endmodule
