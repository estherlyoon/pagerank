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
localparam INT_W = 8;
// length of array to sum
localparam V_LEN = 64;

// data states
localparam WAIT = 0;
localparam READ = 1;
localparam COMPUTE = 2;

wire [INT_W-1:0] lvals [V_LEN-1:0];
wire [INT_W-1:0] rvals [V_LEN-1:0];
 

// read interface
always @(*) begin
	arid_m = 0;
	araddr_m = 0;
	arlen_m = 0; // I don't think this should change?
	arsize_m = 3'b110; // 64 bytes transferred per burst
	arvalid_m = 0;

	rready_m = 1; // read data and response info can be accepted

	/* ivec = rdata_m; */

	/* if (data_state == READ) begin */
	if (0) begin
		araddr_m = curr_addr;
		arlen_m = 0;
		arvalid_m = 1;
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

// vector read state (addr to read from, # ints to read)
reg [63:0] base_addr;                      
reg [31:0] base_words;
reg [63:0] curr_addr;
reg [31:0] curr_words;

// TODO loop between read/write/compute states
always @(posedge clk) begin
	case(0) // TODO
		WAIT: begin
			// wait for start
			curr_addr <= base_addr;
			curr_words <= base_words;

			if (softreg_req_valid & softreg_req_isWrite & softreg_req_addr == `READ_INFO)
				$display("TODO");
		end
		READ: begin
			// read vector
			if (arready_m) begin
				curr_addr <= curr_addr + 64;
				curr_words <= curr_words - 1;
			end
		end
		COMPUTE: begin
		end
	endcase

	if (softreg_req_valid & softreg_req_isWrite) begin
		case(softreg_req_addr)
			`READ_ADDR: base_addr <= softreg_req_data;
			`READ_WORDS: base_words <= softreg_req_data;
		endcase
	end

	if (rst)
		$display("TODO");
end


// TODO PageRank logic

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
