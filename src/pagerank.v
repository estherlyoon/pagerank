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
localparam RATIO = 4;
localparam LOG_R = $clog2(RATIO);

// pr states
localparam WAIT = 0;
localparam READ_VERT = 1;
localparam READ_INEDGES = 2;
localparam CONTROL = 3;
reg [7:0] pr_state = 0;

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
	arlen_m = 0; // specifies # transfers per burst, 1 is default I think, not sure if should change
	arsize_m = 3'b011; // 8 bytes transferred per burst
	arvalid_m = 0;

  	// indicates read data and response info can be accepted
	rready_m = 1;

	vert_fifo_wrreq = rvalid_m && (rid_m == 0)
	vert_fifo_in = rdata_m;

	/* inedge_fifo_wrreq = rvalid_m && (rid_m == 1) */
	/* inedge_fifo_in = rdata_m; */

	// TODO fields for determining stride
	
	case(pr_state)
		0: begin
			arid_m = 0;
			araddr_m = v_addr;
			arlen_m = 0; // TODO ?
  			// only request reads when fifo is empty
			arvalid_m = 1 & !vert_fifo_full;
		end
		1: begin
			arid_m = 1;       
			araddr_m = ie_addr;
			arlen_m = 0; // TODO ?
			arvalid_m = 1;
		end
	end
end

// write interface TODO
always @(*) begin
	awid_m = 0;
	awaddr_m = 0;
	awlen_m = 0;
	awsize_m = 3'b110; // 64 bytes transferred per burst
	awvalid_m = 0; // address is valid

	wid_m = 0;
	wdata_m = 0; // TODO output array
	wstrb_m = 64'hFFFFFFFFFFFFFFFF;
	wlast_m = 0;
	wvalid_m = 0;

	bready_m = 1;
end

// vector read states
// start of vertice array
reg [63:0] v_base_addr;                      
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
reg [LOG_R-1:0] read_count; // TODO LOG_R bits?

// id of current vertex being processed
reg [63:0] vert_processing;

// read in all vertices, all in-edges. when done with current round, repeat
always @(posedge clk) begin
	case(pr_state)
		WAIT: begin
			// wait for start
			v_addr <= v_base_addr;
			vert_to_fetch <= n_vertices;
			ie_addr <= ie_base_addr;
			ie_to_fetch <= n_inedges;
			read_count <= 0;

			if (softreg_req_valid & softreg_req_isWrite & softreg_req_addr == `READ_PARAMS)
				pr_state <= READ_VERT;
		end                
		READ_VERT: begin
			// read in one element from vertex array
			if (arready_m) begin
				v_addr <= v_addr + INT_W/8;
				vert_to_fetch <= vert_to_fetch - 1;
				pr_state <= READ_INEDGES;
			end  
		end
		READ_INEDGES: begin
			if (arready_m) begin
				ie_addr <= ie_addr + INT_W/8;	
				ie_to_fetch <= ie_to_fetch - 1;	
			end
			pr_state <= CONTROL;
		end
		CONTROL: begin
			read_count <= read_count + 1;
			if (read_count > RATIO-1)
				pr_state <= READ_INEDGES;
			else if (vert_to_fetch > 0)
				pr_state <= READ_VERT;
			else
				pr_state <= WAIT;
		end
	endcase

	if (softreg_req_valid & softreg_req_isWrite) begin
		case(softreg_req_addr)
			`READ_ADDR: base_addr <= softreg_req_data;
			`READ_WORDS: base_words <= softreg_req_data;
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


// PageRank logic

// output logic
reg sr_resp_valid;
reg [63:0] sr_resp_data;
assign softreg_resp_valid = sr_resp_valid;
assign softreg_resp_data = sr_resp_data;

always @(posedge clk) begin 
	sr_resp_valid <= softreg_req_valid & !softreg_req_isWrite;
	if (softreg_req_valid & !softreg_req_isWrite & softreg_req_addr == `ROUND_DONE)
		sr_resp_data <= 0; // TODO 
end

endmodule
