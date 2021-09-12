`include "src/constants.v"
 
module Pfxsum(
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

// pfxsum states
localparam UP = 0;
localparam INT = 1;
localparam DOWN = 2;
localparam SUM_DONE = 3;

// to transition between reads
reg [7:0] data_state = WAIT;
// to transition between states of pfxsum execution
reg [7:0] pfxsum_state = UP;
reg [63:0] total_sum;
// current level for sweep, log2-based
reg [15:0] level = 0;
// input vector 
reg [511:0] ivec;
// output vector 
reg [511:0] ovec;
// in-place array to compute pfxsum
reg [INT_W-1:0] vec [V_LEN-1:0];
// logic to check state
reg zeroed;
reg data_ready;
reg once = 0;
reg sum_done;
reg all_done;
reg [7:0] data_delay;

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

	ivec = rdata_m;

	if (data_state == READ) begin
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
	awvalid_m = sum_done; // address is valid

	wid_m = 0;
	wdata_m = ovec;
	wstrb_m = 64'hFFFFFFFFFFFFFFFF;
	wlast_m = all_done;
	wvalid_m = sum_done; // write data is valid

	bready_m = 1;
end

// vector read state (addr to read from, # ints to read)
reg [63:0] base_addr;                      
reg [31:0] base_words;
reg [63:0] curr_addr;
reg [31:0] curr_words;

always @(posedge clk) begin
	case(data_state)
		WAIT: begin
			// wait for start
			curr_addr <= base_addr;
			curr_words <= base_words;
			data_delay <= 2;

			if (softreg_req_valid & softreg_req_isWrite & softreg_req_addr == `READ_INFO)
				data_state <= READ;
		end
		READ: begin
			// read vector
			if (arready_m) begin
				curr_addr <= curr_addr + 64;
				curr_words <= curr_words - 1;
				data_delay <= data_delay - 1;
				if (data_delay == 0)
					data_state <= COMPUTE;
			end
		end
		COMPUTE: begin
			// start pfxsum computation
			// TODO reset after each sum
		end
	endcase

	if (softreg_req_valid & softreg_req_isWrite) begin
		case(softreg_req_addr)
			`READ_ADDR: base_addr <= softreg_req_data;
			`READ_WORDS: base_words <= softreg_req_data;
		endcase
	end

	if (rst)
		data_state <= 0;
end

genvar n;
generate
for (n = 0; n < V_LEN; n = n + 1) begin
	assign lvals[n] = n + 2 ** level - 1;
	assign rvals[n] = n + 2 ** (level + 1) - 1;

	always @(*) begin
		// reflatten vec for output
		ovec[(n+1)*INT_W-1:n*INT_W] = vec[n];
	end
	
	always @(posedge clk) begin
		// initialize vec, unflatten into 2d array
		if (data_delay == 1 && !once) begin
			vec[n] <= ivec[(n+1)*INT_W-1:n*INT_W];
			once <= 1;
		end

		if (data_state == COMPUTE & rvals[n] < V_LEN & n % (2 ** (level+1)) == 0) begin
			if (pfxsum_state == UP) begin
				vec[rvals[n]] <= vec[lvals[n]] + vec[rvals[n]];
			end
			if (pfxsum_state == DOWN) begin
				vec[lvals[n]] <= vec[rvals[n]];
				vec[rvals[n]] <= vec[lvals[n]] + vec[rvals[n]];
			end
		end
	end
end
endgenerate

// state machine for pfxsum stages
always @(posedge clk) begin
	if (data_state == COMPUTE) begin
		case(pfxsum_state)
			UP: begin
				// check if done with up-sweep
				if (level == $clog2(V_LEN) - 1)
					pfxsum_state <= INT;
				else level <= level + 1;
			end
			INT: begin
				// save sum, zero out top element
				total_sum <= vec[V_LEN-1];
				vec[V_LEN-1] <= 0;
				pfxsum_state <= DOWN;
			end
			DOWN: begin
				level <= level - 1;
				if (level == 0) pfxsum_state <= SUM_DONE;
			end
			SUM_DONE: begin
				sum_done <= 1;
			end
		endcase
	end
end

// output logic
reg sr_resp_valid;
reg [63:0] sr_resp_data;
assign softreg_resp_valid = sr_resp_valid;
assign softreg_resp_data = sr_resp_data;

always @(posedge clk) begin 
	sr_resp_valid <= softreg_req_valid & !softreg_req_isWrite;
	if (softreg_req_valid & !softreg_req_isWrite & softreg_req_addr == `ROUND_DONE)
		sr_resp_data <= total_sum;
end

// DEBUG
genvar i;
generate
for (i = 0; i < V_LEN; i = i + 1) begin
	always @(posedge clk) begin
		/* if (pfxsum_state == UP & level == 0 | $clog2(V_LEN) - 1 == level + 1) $display("up %d: %h", i, vec[i]); */
		//if (pfxsum_state == DOWN) $display("arr %d: %h", i, vec[i]);
	end
end
endgenerate

endmodule
