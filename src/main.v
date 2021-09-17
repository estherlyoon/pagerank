`include "src/constants.v"

module main;
 
reg clk = 0;
always #5 clk = !clk;
reg [31:0] count = 0;
always @(posedge clk) count <= count + 1;


// AXI memory interface
wire [15:0] arid_m;
wire [63:0] araddr_m;
wire [7:0]  arlen_m;
wire [2:0]  arsize_m;
wire        arvalid_m;
wire        arready_m;

wire [15:0]  rid_m;
wire [511:0] rdata_m;
wire [1:0]   rresp_m;
wire         rlast_m;
wire         rvalid_m;
wire         rready_m;

wire [15:0] awid_m;
wire [63:0] awaddr_m;
wire [7:0]  awlen_m;
wire [2:0]  awsize_m;
wire        awvalid_m;
wire        awready_m;

wire [15:0]  wid_m;
wire [511:0] wdata_m;
wire [63:0]  wstrb_m;
wire         wlast_m;
wire         wvalid_m;
wire         wready_m;

wire [15:0] bid_m;
wire [1:0]  bresp_m;
wire        bvalid_m;
wire        bready_m;

// SoftReg interface
reg        softreg_req_valid;
reg        softreg_req_isWrite;
reg [31:0] softreg_req_addr;
reg [63:0] softreg_req_data;

wire        softreg_resp_valid;
wire [63:0] softreg_resp_data;

always @(*) begin
	case (count)
	32'd3: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 1;
		softreg_req_addr = `READ_PARAMS; // read # vertices and edges (first two words)
		softreg_req_data = 64'h0;
	end
	32'd4: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 1;
		softreg_req_addr = `READ_VMAP;
		softreg_req_data = 64'd4;
	end
	32'd8: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 1;
		softreg_req_addr = 32'h28; // # iters TODO
		softreg_req_data = 64'd256;
	end
	32'd9: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 1;
		softreg_req_addr = 32'h30;  // write address TODO
		softreg_req_data = 64'h200; // random place to write data?
	end
	32'd10: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 1;
		softreg_req_addr = `READ_INFO; // start pfxsum 
		softreg_req_data = 64'd4;
	end
	32'd1000: begin
		softreg_req_valid = 1;
		softreg_req_isWrite = 0;
		softreg_req_addr = `ROUND_DONE; // one round of sum done
		softreg_req_data = 64'h0;
	end
	default: begin
		softreg_req_valid = 0;
		softreg_req_isWrite = 0;
		softreg_req_addr = 0;
		softreg_req_data = 0;
	end
	endcase
end
always @(posedge clk) begin
	if (softreg_resp_valid) begin
		$display("total sum: %d", softreg_resp_data);
		$finish(0);
	end
end

// instantiations
axi_emu #(
	.WORDS(9)
) ae (
	.clk(clk),
	.rst(rst),
	
	.arid_m(arid_m),
	.araddr_m(araddr_m),
	.arlen_m(arlen_m),
	.arsize_m(arsize_m),
	.arvalid_m(arvalid_m),
	.arready_m(arready_m),
	
	.rid_m(rid_m),
	.rdata_m(rdata_m),
	.rresp_m(rresp_m),
	.rlast_m(rlast_m),
	.rvalid_m(rvalid_m),
	.rready_m(rready_m),
	
	.awid_m(awid_m),
	.awaddr_m(awaddr_m),
	.awlen_m(awlen_m),
	.awsize_m(awsize_m),
	.awvalid_m(awvalid_m),
	.awready_m(awready_m),
	
	.wid_m(wid_m),
	.wdata_m(wdata_m),
	.wstrb_m(wstrb_m),
	.wlast_m(wlast_m),
	.wvalid_m(wvalid_m),
	.wready_m(wready_m),
	
	.bid_m(bid_m),
	.bresp_m(bresp_m),
	.bvalid_m(bvalid_m),
	.bready_m(bready_m)
);

PageRank pagerank(
	.clk(clk),
	.rst(rst),
	
	.arid_m(arid_m),
	.araddr_m(araddr_m),
	.arlen_m(arlen_m),
	.arsize_m(arsize_m),
	.arvalid_m(arvalid_m),
	.arready_m(arready_m),
	
	.rid_m(rid_m),
	.rdata_m(rdata_m),
	.rresp_m(rresp_m),
	.rlast_m(rlast_m),
	.rvalid_m(rvalid_m),
	.rready_m(rready_m),
	
	.awid_m(awid_m),
	.awaddr_m(awaddr_m),
	.awlen_m(awlen_m),
	.awsize_m(awsize_m),
	.awvalid_m(awvalid_m),
	.awready_m(awready_m),
	
	.wid_m(wid_m),
	.wdata_m(wdata_m),
	.wstrb_m(wstrb_m),
	.wlast_m(wlast_m),
	.wvalid_m(wvalid_m),
	.wready_m(wready_m),
	
	.bid_m(bid_m),
	.bresp_m(bresp_m),
	.bvalid_m(bvalid_m),
	.bready_m(bready_m),
	
	.softreg_req_valid(softreg_req_valid),
	.softreg_req_isWrite(softreg_req_isWrite),
	.softreg_req_addr(softreg_req_addr),
	.softreg_req_data(softreg_req_data),
	
	.softreg_resp_valid(softreg_resp_valid),
	.softreg_resp_data(softreg_resp_data)
);
  
endmodule
