`include "src/constants.v"

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
);

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

// logic states
localparam L_VERT = 0;
localparam L_IE_VERT = 1;
localparam L_IE_PR = 2;
localparam L_WRITE = 3;
reg [7:0] logic_state = 0;

// divider
reg din = 0;
reg dset = 0;
reg [INT_W-1:0] dividend;
reg [INT_W/2-1:0] divisor;
wire [INT_W/2-1:0] quotient;
wire [INT_W/2-1:0] remainder;
wire div0, ovf, dout;

div_uu #(INT_W) div (
	.clk(clk),
	.ena(1'b1),
	.iready(din),
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

// counters and parameters
// total number of PageRank iterations to complete
reg [63:0] total_rounds;
// number of iterations completed so far
reg [63:0] round = 0;

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

	v_rready = rvalid_m & (rid_m == 0);
	v_rdata = rdata_m;
	v_odata_req = !vert_fifo_full;
	vert_fifo_wrreq = v_oready;
	vert_fifo_in = v_odata;

	ie_rready = rvalid_m & (rid_m == 1);
	ie_rdata = rdata_m;
	ie_odata_req = !inedge_fifo_full;
	inedge_fifo_wrreq = ie_oready;
	inedge_fifo_in = ie_odata;

	pr_rready = rvalid_m & (rid_m == 2);
	pr_rdata = rdata_m;

	case(pr_state)
		READ_VERT: begin
			arid_m = 0;
			araddr_m = v_addr;
			arlen_m = 0;
			// only request reads when buffer is ready to accept data
			arvalid_m = !v_oready;
		end
		READ_INEDGES: begin
			arid_m = 1;
			araddr_m = ie_addr;
			arlen_m = 0;
			arvalid_m = !ie_oready;
		end
		READ_PR: begin
			arid_m = 2;
			araddr_m = pr_raddr;
			arlen_m = 0;
			arvalid_m = logic_state == L_IE_PR;
		end
	endcase
end

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

/* data read logic to read in some # vertices -> some # in-edge vertices -> random PR reads
/* currently round-robin between read types, but if streaming buffers are full,
/* will keep performing random reads
 */
always @(posedge clk) begin
	case(pr_state)
		// wait for start of each round
		WAIT: begin
			v_addr <= v_base_addr;
			vert_to_fetch <= n_vertices;
			v_base <= 0;
			v_bounds <= 8; // TODO handle < 4 for total vertices (not critical)

			ie_addr <= ie_base_addr;
			ie_to_fetch <= n_inedges;
			ie_batch <= 4;
			ie_base <= ie_base_addr[5:3];
			ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch : 512/INT_W;

			wait_priority <= 0;

			if (round == 0 & softreg_req_valid & softreg_req_isWrite) begin
				if (softreg_req_addr == `DONE_READ_PARAMS) begin
					// for debugging
					$display("n_vertices: %0d", n_vertices);
					$display("n_inedges: %0d", n_inedges);
					$display("total_rounds: %0d", total_rounds);
					$display("pr_raddr: 0x%x", base_pr_raddr);
					$display("pr_waddr: 0x%x", base_pr_waddr);
					$display("dividend = %b, divisor = %b", 1 << (PREC*2), n_vertices << PREC);

					// compute the initial PR value
					dividend <= 1 << PREC;
					divisor <= n_vertices;
					din <= 1;
					round <= 1;
				end
			end
			else if (round > 0) begin
				if (round == total_rounds) $finish();
				// first round
				else if (round == 1) begin
					din <= 0;
					// wait for division to complete
					if (dout) begin
						init_val <= quotient;
						pr_state <= READ_VERT;
						round <= round + 1;
						$display("\n*** Round 1: quotient is %b, remainder %b ***\n", 
												quotient, remainder);
					end
				end
				// all other rounds
				else begin
					pr_state <= READ_VERT;
					round <= round + 1;
					$display("\n\n*** Starting Round: %0d ***\n", round);
				end
			end
		end
		READ_VERT: begin
			// read in up to 4 (n_in_edge,n_out_edge) pairs in one read
			if (arready_m & arvalid_m) begin
				v_addr <= v_addr + 64;
				v_base <= 0;
				v_bounds <= vert_to_fetch < 512/(INT_W*2) ? vert_to_fetch : 512/(INT_W*2);

				if (vert_to_fetch <= 512/(INT_W*2))	vert_to_fetch <= 0;
				else vert_to_fetch <= vert_to_fetch - 512/(INT_W*2);

				pr_state <= READ_INEDGES;
			end  
			else if (vert_to_fetch == 0 | vert_fifo_full)
				pr_state <= READ_INEDGES;
		end
		READ_INEDGES: begin
			if (arready_m & arvalid_m) begin
				ie_addr <= ie_addr[5:3] == 0 ? ie_addr+64 : ie_addr+64-(ie_addr[5:3] << 3); // * 512/INT_W;	
				ie_base <= ie_addr[5:3];
				ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch : 512/INT_W;

				if (ie_to_fetch <= 512/INT_W) ie_to_fetch <= 0;
				else ie_to_fetch <= ie_to_fetch - 512/INT_W + ie_addr[5:3];

				ie_batch <= ie_batch - 1;
			end

			else if (inedge_fifo_full)
				pr_state <= READ_PR;
			else if (ie_to_fetch == 0 | ie_batch == 0)
				pr_state <= CONTROL;
		end
		READ_PR: begin
			if (arready_m & arvalid_m) begin
				pr_state <= CONTROL;
			end

			if (wait_priority) // check in other stages?
				pr_state <= WAIT;
			else if (vert_fifo_empty)
				pr_state <= READ_VERT;
		end
		CONTROL: begin
			if (vert_to_fetch > 0 & !v_oready)
				pr_state <= READ_VERT;
			else if (ie_to_fetch > 0 & !ie_oready)
				pr_state <= READ_INEDGES;
			else
				pr_state <= READ_PR;
			/* else */ // TODO conditions for this
			/* 	pr_state <= WAIT; */
		end
	endcase

	if (softreg_req_valid & softreg_req_isWrite) begin
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

	if (rst)
		pr_state <= WAIT;
end

// FIFO for vertex in-edges offset + # out-edges stored as a pair
HullFIFO #(
	.TYPE(0),
	.WIDTH(128),
	.LOG_DEPTH(4) // buffer 16 vertices at once
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
 	// buffer 16 vertices at once
	.LOG_DEPTH(4)
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

AddrParser #(
	.FULL_WIDTH(512),
	.WIDTH(64)
) parser (
	pr_rready,
	pr_raddr[5:3],
	pr_rdata,
	pr_odata
);

reg pr_wvalid = 0;
reg pr_awvalid = 0;
reg [INT_W-1:0] v_count = 0;
reg [INT_W*2-1:0] v_outedges;
reg [INT_W-1:0] n_ie_left;
reg [INT_W-1:0] ie_curr;
reg [INT_W-1:0] pr_sum = 0;
reg [INT_W-1:0] pagerank;

assign vert_fifo_rdreq = logic_state == L_VERT;
assign inedge_fifo_rdreq = logic_state == L_IE_VERT;

// PageRank logic
always @(posedge clk) begin

	case(logic_state)
		// read next vertex
		L_VERT: begin
			if (!vert_fifo_empty) begin
				/* $display("VERTEX (%0d, %0d)", vert_fifo_out[INT_W*2-1:INT_W], vert_fifo_out[INT_W-1:0]); */
				v_outedges <= vert_fifo_out[INT_W-1:0];
				n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W];
				pr_sum <= 0;
				logic_state <= L_IE_VERT;
			end
		end
		// read next in-edge vertex
		L_IE_VERT: begin
			if (!inedge_fifo_empty) begin
				$display("\tIE -- %0d", inedge_fifo_out);
				ie_curr <= inedge_fifo_out;
				pr_raddr <= base_pr_raddr + (inedge_fifo_out << 3);
				logic_state <= L_IE_PR;
			end 
		end
		L_IE_PR: begin
			pr_waddr <= base_pr_waddr + (v_count << 3);
			pr_awvalid <= 1;

			// perform division of PR sum by # outedges
			if (n_ie_left <= 1) begin
				divisor <= v_outedges;
				dividend <= pr_sum;

				if (!dset) begin
					din <= 1;
					dset <= 1;
				end
				else din <= 0;

				if (dout) begin
					pagerank <= quotient;
					pr_awvalid <= 0;
					pr_wvalid <= 1;
					logic_state <= L_WRITE;
					/* $display("quotient: %b", quotient); */
					/* $display("pagerank for vertex %0d is %0d/%0d = %0d", */
						/* v_count, pr_sum, v_outedges, pr_sum / v_outedges); */
				end
			end
			else if (round == 2 | pr_rready) begin
				// fetch PR of current in-edge vertex, add it to running sum
				if (round == 2) begin
					$display("\tsetting init_val of %0d to %0d", ie_curr, init_val);
					pr_sum <= pr_sum + init_val;
				end
				else if (pr_rready) begin
					$display("\tpr_odata for %0d = %h", ie_curr, pr_odata);
					pr_sum <= pr_sum + pr_odata;
				end

				// ready to read in next ie vertex
				n_ie_left <= n_ie_left - 1;
				if (n_ie_left > 1)
					logic_state <= L_IE_VERT;
			end
		end
		L_WRITE: begin
			if (wvalid_m & wready_m) begin
				$display("---------------- WRITING %b to 0x%0h ----------------", pagerank, pr_waddr);
				pr_wvalid <= 0;
				v_count <= v_count + 1;
				logic_state <= L_VERT;
				dset <= 0;
			end
		end
	endcase

	if (v_count == n_vertices) begin
		$display("*** Done with round %0d of PR ***", round-1);
		base_pr_waddr <= base_pr_raddr;
		base_pr_raddr <= base_pr_waddr;
		v_count <= 0;
		wait_priority <= 1;
		logic_state <= L_VERT; // TODO race condition with L_IE_PR logic set?
	end
end

// output logic
reg sr_resp_valid;
reg [63:0] sr_resp_data;
assign softreg_resp_valid = sr_resp_valid;
assign softreg_resp_data = sr_resp_data;

always @(posedge clk) begin 
	sr_resp_valid <= softreg_req_valid & !softreg_req_isWrite;
	if (softreg_req_valid & !softreg_req_isWrite & softreg_req_addr == `DONE_ALL)
		sr_resp_data <= 0; // TODO 
end

endmodule
