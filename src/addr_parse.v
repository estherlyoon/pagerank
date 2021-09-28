// reads out subsection of data based on provided indices
// TODO ask joshua- do bit shifting to multiply here instead and pass in log(width)?
module AddrParser #(
	parameter FULL_WIDTH = 512,
	parameter WIDTH = 64
) (
	input [2:0] idx, // TODO scale with width, log(width/8)
	input [0:FULL_WIDTH-1] in,
	output [WIDTH-1:0] out
);

assign out = in[WIDTH*idx+:WIDTH];

endmodule
