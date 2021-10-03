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
localparam RATIO = 4; // number of empty slots in in-edge 
localparam LOG_R = $clog2(RATIO);
localparam BYTE = 8;

// pr states
localparam WAIT = 0;
localparam READ_VERT = 1;
localparam READ_INEDGES = 2;
localparam READ_PR = 3;
localparam CONTROL = 4;
reg [7:0] pr_state = 0;
 
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
			arvalid_m = !ie_ready;
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
	awvalid_m = pr_awvalid; // ?

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

// TODO problem: how to prioritize certain reads over others
	// in each stage, if a pagerank request is pending, read that?

// read in all vertices, all in-edges. when done with current round, repeat
always @(posedge clk) begin
	case(pr_state)
		// wait for start
		WAIT: begin
			v_addr <= v_base_addr;
			vert_to_fetch <= n_vertices;
			v_base <= 0;
			v_bounds <= 8; // TODO handle < 4 for total vertices (not super important)

			ie_addr <= ie_base_addr;
			ie_to_fetch <= n_inedges;
			ie_batch <= 4;
			ie_base <= ie_base_addr[5:3];
			ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch : 512/INT_W;

			if (round == 0 & softreg_req_valid & softreg_req_isWrite) begin
				if (softreg_req_addr == `DONE_READ_PARAMS) begin
            		$display("n_vertices: %d", n_vertices);
            		$display("n_inedges: %d", n_inedges);
            		$display("total_rounds: %d", total_rounds);
            		$display("pr_raddr: %x", base_pr_raddr);
            		$display("pr_waddr: %x", base_pr_waddr);

					// store 1/n_vertices; very first round, get this value, divide by n_out, then get pr
					init_val <= 1; // / n_vertices; TODO divider
					round <= 1;
					pr_state <= READ_VERT;
				end
			end
			else if (round > 0) begin
				if (round == total_rounds) $finish();
				else pr_state <= READ_VERT;
				round <= round + 1;
				$display("\n*** Starting Round: %d with addr %x ***\n", round, base_pr_waddr);
			end
		end                
		READ_VERT: begin
			// read in up to 4 vertices+n_out_edge pairs in one read
			if (arready_m & arvalid_m) begin
				v_addr <= v_addr + 64;
				v_base <= 0;
				v_bounds <= vert_to_fetch < 512/(INT_W*2) ? vert_to_fetch : 512/(INT_W*2);

				if (vert_to_fetch <= 512/(INT_W*2))	vert_to_fetch <= 0;
				else vert_to_fetch <= vert_to_fetch - 512/(INT_W*2);

				pr_state <= READ_INEDGES; // TODO scheme
			end  

			if (vert_to_fetch == 0)
				pr_state <= READ_INEDGES;
		end
		READ_INEDGES: begin
			if (arready_m & arvalid_m) begin
				ie_addr <= ie_addr[5:3] == 0 ? ie_addr + 64 : ie_addr + 64 - (ie_addr[5:3] << 3); // * 512/INT_W;	
				ie_base <= ie_addr[5:3];
				ie_bounds <= ie_to_fetch < 512/INT_W ? ie_to_fetch : 512/INT_W;

                if (ie_to_fetch <= 512/INT_W) ie_to_fetch <= 0;
				else ie_to_fetch <= ie_to_fetch - 512/INT_W + ie_addr[5:3];

				ie_batch <= ie_batch - 1; // this represents fullness level of FIFO

				if (!ie_oready)
					pr_state <= READ_PR;
				else if (ie_to_fetch == 0 | ie_batch == 0)
					pr_state <= CONTROL;
			end

		end
		READ_PR: begin
			if (arready_m & arvalid_m) begin
				pr_raddr <= base_pr_raddr + (ie_curr << 3); // multiply by 8
				pr_state <= CONTROL;
			end
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
			`N_ROUNDS: total_rounds <= softreg_req_data;
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
	.WIDTH(64), // maybe? id + offset = 2 * 64
	.LOG_DEPTH(4) // buffer 16 vertices at once
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
 
// TODO problem: how to get #in-edges
	// 1: subtract next offset from yours-- where to do this?
		// ask joshua
	// 2: do it during graph pre-processing
reg v_ready = 1;
reg ie_ready = 1;
reg ie_readstate = 0;
reg pr_wvalid = 0;
reg pr_awvalid = 0;
reg [INT_W-1:0] v_count = 0;
reg [INT_W*2-1:0] v_outedges;
reg [INT_W-1:0] n_ie_left;
reg [INT_W-1:0] ie_curr;
reg [INT_W-1:0] pagerank = 0;

assign vert_fifo_rdreq = v_ready;
assign inedge_fifo_rdreq = ie_ready & !v_ready;

// PageRank logic
always @(posedge clk) begin
	// read next vertex
	if (!vert_fifo_empty & v_ready) begin
		$display("VERTEX (%d, %d)", vert_fifo_out[INT_W*2-1:INT_W], vert_fifo_out[INT_W-1:0]);
		v_ready <= 0;
		v_outedges <= vert_fifo_out[INT_W-1:0];
		n_ie_left <= vert_fifo_out[INT_W*2-1:INT_W];
		pagerank <= 0;
	end
 
	// read next in-edge vertex
	if (!inedge_fifo_empty & inedge_fifo_rdreq) begin
		/* $display("IE -- %h", inedge_fifo_out); */
		ie_ready <= 0; // ready to process another in-edge vertex
		// TODO put a state here for reading PR, ie_ready is too overloaded
		// current problem: arvalid set bc !ie_ready, reading garbage 
		// before base_addr is updated in new round
		ie_curr <= inedge_fifo_out;
	end 

    // fetch PR of current in-edge vertex, add it to running sum
	if (!ie_ready & pr_rready) begin
		if (round == 1) begin
			$display("setting init_val of %d to %d", ie_curr, init_val);
			pagerank <= pagerank + init_val;
		end
		else begin
			$display("\tpr_odata for %d = %h", ie_curr, pr_odata);
			pagerank <= pagerank + pr_odata; // TODO get specific index to read from
		end

		n_ie_left <= n_ie_left - 1;

		// TODO move?
		pr_waddr <= base_pr_waddr + (v_count << 3); // multiply by INT_W/8
		pr_awvalid <= 1;

		/* if (n_ie_left == 1) */
		/* 	$display("set pr_waddr to %h", base_pr_waddr + v_count << 3); */

		if (n_ie_left > 1)
			ie_ready <= 1;
		else begin
			// done with sum, divide it by # outedges, writeback data, reset pagerank afterwards
			// TODO put these things in a divider, might need to save vertex id for writeback
			$display("\tpagerank for vertex %d is %d/%d = %d", v_count, pagerank, v_outedges, pagerank / v_outedges);
			pr_awvalid <= 0;
			pr_wvalid <= 1;
		end
	end

	if (wvalid_m & wready_m) begin
		$display("----------------WRITING %h ----------------", pr_waddr);
		pr_wvalid <= 0;
		ie_ready <= 1;
		v_ready <= 1;
		v_count <= v_count + 1;
	end

	if (v_count == n_vertices) begin
		$display("*** Done performing round %d of PR ***", round);
		base_pr_waddr <= base_pr_raddr;
		base_pr_raddr <= base_pr_waddr;
		v_count <= 0;
		pr_state <= WAIT;
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
