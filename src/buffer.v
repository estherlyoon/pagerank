// stores larger reads in a buffer, fetching segments until buffer is empty
// note: bounds is exclusive, so elements from [base,bounds) will be fetched
module ReadBuffer #(
	parameter FULL_WIDTH = 512,
	parameter WIDTH = 64
) (
	input clk,
	input rready,
	input [FULL_WIDTH-1:0] rdata,
	input odata_req,
	input [7:0] base,
	input [7:0] bounds,
	// if data exists in the buffer to fetch
	output oready,
	output [WIDTH-1:0] odata
);

localparam MAX_ELEMS = FULL_WIDTH/WIDTH;

reg [WIDTH-1:0] buffer [MAX_ELEMS-1:0];
reg [WIDTH-1:0] odata_;
reg [7:0] buffer_elems = 0;
reg [7:0] rdptr;
reg [7:0] bounds_;

assign odata = odata_;
assign oready = buffer_elems != 0;

genvar i;
generate
for (i = 0; i < MAX_ELEMS; i = i + 1)begin
	always @(posedge clk) begin
		if (rready & !oready)
			buffer[MAX_ELEMS-i-1] <= rdata[WIDTH*i-1:WIDTH*(i-1)];
	end
end
endgenerate

always @(posedge clk) begin
	if (rready & !oready) begin
		buffer_elems <= MAX_ELEMS;
		rdptr <= base < MAX_ELEMS ? base : 0;
		bounds_ <= base + bounds <= MAX_ELEMS ? bounds : MAX_ELEMS;
		$display("setting bounds to %d", base);
	end

	if (oready & odata_req) begin
		buffer_elems <= buffer_elems - 1;
		odata_ <= buffer[rdptr];
		rdptr <= rdptr + 1;
		bounds_ <= bounds - 1;
		if (buffer_elems == 0 | bounds_ == 0) begin
			// we can accept data again
			buffer_elems <= 0;
		end
	end
end
endmodule

 
