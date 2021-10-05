module axi_emu #(
	parameter WORDS = 1
) (
	input clk,
	input rst,
	
	input [15:0] arid_m,
	input [63:0] araddr_m,
	input [7:0]  arlen_m,
	input [2:0]  arsize_m,
	input        arvalid_m,
	output       arready_m,
	
	output [15:0]  rid_m,
	output [511:0] rdata_m,
	output [1:0]   rresp_m,
	output         rlast_m,
	output         rvalid_m,
	input          rready_m,
	
	input [15:0] awid_m,
	input [63:0] awaddr_m,
	input [7:0]  awlen_m,
	input [2:0]  awsize_m,
	input        awvalid_m,
	output       awready_m,
	
	input [15:0]  wid_m,
	input [511:0] wdata_m,
	input [63:0]  wstrb_m,
	input         wlast_m,
	input         wvalid_m,
	output        wready_m,
	
	output [15:0] bid_m,
	output [1:0]  bresp_m,
	output        bvalid_m,
	input         bready_m
);

// physical memory
reg [511:0] mem [WORDS-1:0];
initial begin
	$readmemh("./mem_init.hex", mem);
end


// read channel logic
reg [15:0] arid;
reg [63:0] araddr;
reg [7:0] arlen;   // TODO: verify page boundaries
reg [2:0] arsize;  // TODO: handle properly

reg [1:0] ar_state = 0;

assign arready_m = ar_state == 2'h0;
assign rvalid_m  = ar_state == 2'h1;

assign rid_m = arid;
assign rdata_m = mem[araddr[63:6]];
assign rresp_m = (araddr[63:6] >= WORDS) ? 2'h2: 2'h0;
assign rlast_m = arlen == 8'h0;

always @(posedge clk) begin
	if (rst) begin
		ar_state <= 2'h0;
	end else begin
		case (ar_state)
		2'h0: begin
			if (arvalid_m) begin
				arid <= arid_m;
				araddr <= araddr_m;
				arlen <= arlen_m;
				arsize <= arsize_m;
				
				ar_state <= 2'h1;
			end
		end
		2'h1: begin
			if (rready_m) begin
				if (arlen == 0) begin
					ar_state <= 2'h0;
				end
				
				arlen <= arlen - 8'h1;
				araddr <= araddr + 64'd64;
			end
		end
		endcase
	end
end


// write channel logic
reg [15:0] awid;
reg [63:0] awaddr;
reg [7:0] awlen;   // TODO: verify page boundaries and length
reg [2:0] awsize;  // TODO: handle properly

reg [1:0] aw_state = 0;

assign awready_m = aw_state == 2'h0;
assign wready_m  = aw_state == 2'h1;
assign bvalid_m  = aw_state == 2'h2;

assign bid_m = awid;
assign bresp_m = 2'b00;

reg [511:0] line;
genvar g;
generate
for (g=0; g<64; g=g+1) begin
	always @(*) begin
		line[8*g+7:8*g] = wstrb_m[g] ? wdata_m[8*g+7:8*g] : mem[awaddr[63:6]][8*g+7:8*g];
	end
end
endgenerate

always @(posedge clk) begin
	if (rst) begin
		aw_state <= 0;
	end else begin
		case (aw_state)
		2'h0: begin
			if (awvalid_m) begin
				awid <= awid_m;
				awaddr <= awaddr_m;
				awlen <= awlen_m;
				awsize <= awsize_m;
				
				aw_state <= 1;
			end
		end
		2'h1: begin
			if (wvalid_m) begin
				/* $display("AXI writing line %h", line); */
				mem[awaddr[63:6]] <= line;
				
				awaddr <= awaddr + 64'd64;
				awlen <= awlen - 8'h1;
				if (wlast_m) begin
					aw_state <= 2'h2;
				end
			end
		end
		2'h2: begin
			if (bready_m) begin
				aw_state <= 2'h0;
			end
		end
		endcase
	end
end

endmodule
