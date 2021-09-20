`include "src/constants.v"

// stores larger reads in a buffer, fetching segments until buffer is empty
module ReadBuffer #(
	parameter FULL_WIDTH = 512,
	parameter WIDTH = 64
) (
	input clk,
	input rready,
	input [FULL_WIDTH-1:0] rdata,
	input odata_req,
	// if data exists in the buffer to fetch
	output oready,
	output [WIDTH-1:0] odata
);

localparam MAX_ELEMS = FULL_WIDTH/WIDTH;

reg [WIDTH-1:0] buffer [MAX_ELEMS-1:0];
reg [WIDTH-1:0] odata_;
reg [7:0] buffer_elems = 0;
reg [7:0] rdptr = 0;

assign odata = odata_;
assign oready = buffer_elems != 0;

genvar i;
generate
for (i = 0; i < MAX_ELEMS; i = i + 1)begin
	always @(posedge clk) begin
		if (rready & !oready)
			buffer[i] <= rdata[WIDTH*i-1:WIDTH*(i-1)];
	end
end
endgenerate

always @(posedge clk) begin
	if (rready & !oready)
		buffer_elems <= MAX_ELEMS;

	if (oready & odata_req) begin
		buffer_elems <= buffer_elems - 1;
		odata_ <= buffer[rdptr];
		rdptr <= rdptr + 1;
		if (buffer_elems == 0) begin
			// we can accept data again
			rdptr <= 0;
		end
	end
end
endmodule

 
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

ReadBuffer #(
	.FULL_WIDTH(512),
	.WIDTH(64)
) v_buffer (
	clk,
	input rready, // from axi
	input [FULL_WIDTH-1:0] rdata, // from axi
	input odata_req, // from queue? if queue not full
	output oready, // feed into queue
	output [WIDTH-1:0] // feed into queue
);
 

// length of integers in bits
localparam INT_W = 64;
localparam RATIO = 4; // number of empty slots in in-edge 
localparam LOG_R = $clog2(RATIO);

// pr states
localparam INIT = 0;
localparam WAIT = 1;
localparam READ_VERT = 2;
localparam READ_INEDGES = 3;
localparam CONTROL = 4;
reg [7:0] pr_state = 0;
reg done_init = 0;

// counters and parameters
// total number of PageRank iterations to complete
reg [63:0] total_rounds;
// number of iterations completed so far
reg [63:0] rounds_completed;

// vertex FIFO signals
reg vert_fifo_wrreq;
reg [63:0] vert_fifo_in;
wire vert_fifo_full;
wire vert_fifo_rdreq;
wire [63:0] vert_fifo_out;
wire vert_fifo_empty;


// read interface
always @(*) begin
	arid_m = 0;
	araddr_m = 0; // make sure this is 64-byte aligned
	// make sure arlen doesn't cross page boundaries
	arlen_m = 0; // specifies # transfers per burst, use default; no savings for reading <512 bits
	arsize_m = 3'b011; // 8 bytes transferred per burst
	arvalid_m = 0;

  	// indicates read data and response info can be accepted
	rready_m = 1;

	vert_fifo_wrreq = rvalid_m && (rid_m == 0) && done_init;
	vert_fifo_in = rdata_m[511:448]; // TODO is this correct?

	/* inedge_fifo_wrreq = rvalid_m && (rid_m == 1) */
	/* inedge_fifo_in = rdata_m; */

	// TODO fields for determining stride
	
	case(pr_state)
		INIT: begin
			arid_m = 0;
			araddr_m = 0;
			arlen_m = 0;
			arvalid_m = 1;
			arsize_m = 3'b100; // 16 bytes
		end
		READ_VERT: begin
			arid_m = 0;
			araddr_m = v_addr;
			arlen_m = 0;
  			// only request reads when fifo is empty
			arvalid_m = 1 & !vert_fifo_full;
		end
		READ_INEDGES: begin
			arid_m = 1;       
			araddr_m = ie_addr;
			arlen_m = 0;
			arvalid_m = 1; // TODO & !ie_fifo_full;
		end
	endcase
end

// write interface TODO
/* always @(*) begin */
/* 	awid_m = 0; */
/* 	awaddr_m = 0; */
/* 	awlen_m = 0; */
/* 	awsize_m = 3'b110; // 64 bytes transferred per burst */
/* 	awvalid_m = 0; // address is valid */

/* 	wid_m = 0; */
/* 	wdata_m = 0; // TODO output array */
/* 	wstrb_m = 64'hFFFFFFFFFFFFFFFF; */
/* 	wlast_m = 0; */
/* 	wvalid_m = 0; */

/* 	bready_m = 1; */
/* end */

// vector read states
// start of vertice array
reg [63:0] v_base_addr = 64'h2;
// current address to read vertex info from
reg [63:0] v_addr;                      
// total number of vertices
reg [63:0] n_vertices;
// id of current vertex being fetched
reg [63:0] vert_to_fetch;
// start of in-edge array
reg [63:0] ie_base_addr;                      
// current address to read in-edge # from
reg [63:0] ie_addr;                      
// total number of edges
reg [63:0] n_inedges;
// id of current edge being fetched
reg [63:0] ie_to_fetch;
reg [3:0] ie_batch; // number of in-edges to fetch at "once"

reg [63:0] write_addr0;
reg [63:0] write_addr1;

// id of current vertex being processed
reg [63:0] vert_processing;

// read in all vertices, all in-edges. when done with current round, repeat
always @(posedge clk) begin
	case(pr_state)
		INIT: begin
 		   if (rvalid_m && (rid_m == 0)) begin
			    n_vertices <= rdata_m[511:448]; 
				n_inedges <= rdata_m[447:384];
				v_base_addr <= 2; 
				ie_base_addr <= 2 + rdata_m[63:0] * 8;
				pr_state <= WAIT;
				done_init <= 1;
			end
		end
		WAIT: begin
            $display("n_vertices: %d", n_vertices);
            $display("n_inedges: %d", n_inedges);
			$display("ie_base_addr: %h", ie_base_addr);

			// parameters TODO timing?
			write_addr0 <= ie_base_addr + n_inedges * 8;
			write_addr1 <= ie_base_addr + n_inedges * 8 + n_vertices * 8;

			// wait for start
			v_addr <= v_base_addr;
			vert_to_fetch <= n_vertices;
			ie_addr <= ie_base_addr;
			ie_to_fetch <= n_inedges;
			ie_batch <= 4; // TODO?

			/* if (softreg_req_valid & softreg_req_isWrite & softreg_req_addr == `DONE_READ_PARAMS) */
			pr_state <= READ_VERT;
		end                
		READ_VERT: begin
			// read in one element from vertex array
			if (arready_m & arvalid_m) begin
				$display("rdata all: %h", rdata_m);
				v_addr <= v_addr + INT_W/8;
				vert_to_fetch <= vert_to_fetch - 1;
				/* pr_state <= READ_INEDGES; */
				pr_state <= CONTROL; // TODO remove
			end  
		end
		READ_INEDGES: begin
			if (arready_m & arvalid_m) begin
				ie_addr <= ie_addr + INT_W/8;	
				ie_to_fetch <= ie_to_fetch - 1;	
				// TODO add every time an in-edge is pulled out, subtract 1
				ie_batch <= ie_batch - 1; // this represents fullness level of FIFO
			end
			if (ie_to_fetch == 0 | ie_batch == 0)
				pr_state <= CONTROL;
		end
		CONTROL: begin
			if (vert_to_fetch > 0)
				pr_state <= READ_VERT;
			/* else if (ie_to_fetch > 0) begin */
			/* 	pr_state <= READ_INEDGES; */
			/* end */
			/* else */
			/* 	pr_state <= WAIT; */
		end
	endcase

	if (softreg_req_valid & softreg_req_isWrite) begin
		case(softreg_req_addr)
			`WRITE_ADDR0: write_addr0 <= softreg_req_data;
		endcase
	end

	if (rst)
		pr_state <= WAIT;
end

// FIFO for vertex + offset
HullFIFO #(
	.TYPE(0),
	.WIDTH(64), // maybe? id + offset = 2 * 64
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


reg [7:0] count = 0;
assign vert_fifo_rdreq = !vert_fifo_empty;

// PageRank logic
always @(posedge clk) begin
	if (vert_fifo_rdreq) begin
		$display("%d: %d", count, vert_fifo_out);
		count <= count + 1;
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
