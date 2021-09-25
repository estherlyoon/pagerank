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

assign odata = odata_;
assign oready = buffer_elems != 0;

genvar i;
generate
for (i = 1; i <= MAX_ELEMS; i = i + 1)begin
	always @(posedge clk) begin
		if (rready & !oready)
			buffer[MAX_ELEMS-i] <= rdata[WIDTH*i-1:WIDTH*(i-1)];
	end
end
endgenerate

always @(posedge clk) begin
	if (rready & !oready) begin
		buffer_elems <= base + bounds < MAX_ELEMS ? bounds - base : MAX_ELEMS;
		rdptr <= base < MAX_ELEMS ? base : 0;
	end

	if (oready & odata_req) begin
		buffer_elems <= buffer_elems - 1;
		odata_ <= buffer[rdptr];
		rdptr <= rdptr + 1;
	end
end
endmodule

 
