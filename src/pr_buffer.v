// stores larger reads in a buffer, fetching segments until buffer is empty
// note: bounds is exclusive, so elements from [base,bounds) will be fetched
module ReadBuffer #(
	// size of entire line in bytes
	parameter FULL_WIDTH = 512,
	// size of one element to fetch in bytes
	parameter WIDTH = 64,
	parameter LOG_DEPTH = 4
) (
	input clk,
	input rst,
	input wrreq,
	input [FULL_WIDTH-1:0] wdata,
	input rdreq,
	input last,
	input [7:0] bounds,
	output empty,
	output full,
	output [WIDTH-1:0] rdata
);

localparam MAX_ELEMS = FULL_WIDTH/WIDTH;

reg [WIDTH-1:0] buffer [(1<<LOG_DEPTH)-1:0][MAX_ELEMS-1:0];
reg [7:0] buffer_elems = 0;
reg [7:0] rdptr;

reg [LOG_DEPTH-1:0] rdline = 0;
reg [LOG_DEPTH-1:0] wrline = 0;
reg [LOG_DEPTH:0] lines = 0;

wire [LOG_DEPTH-1:0] rdline1 = rdline + 1;

wire full_ = lines[LOG_DEPTH];
wire empty_ = lines == 0;
assign full = full_;
assign empty = empty_;

reg last_ = 0;
reg [LOG_DEPTH-1:0] last_rdline = 0;
reg [7:0] last_bounds = 0;

assign rdata = buffer[rdline][rdptr];

genvar i;
generate
for (i = 1; i <= MAX_ELEMS; i = i + 1) begin
	always @(posedge clk) begin
		if (wrreq && !full_)
			buffer[wrline][MAX_ELEMS-i] <= wdata[WIDTH*i-1:WIDTH*(i-1)];
	end
end
endgenerate

always @(posedge clk) begin
	if (rst) begin
		wrline <= 0;
		rdline <= 0;
		lines <= 0;
        buffer_elems <= 0;
		$display("buffer_elems = 0");
	end
	else begin
        if (rdreq && buffer_elems == 1 && !empty_ && wrreq && !full_) begin
		end else if (rdreq && buffer_elems == 1 && !empty_) begin
			lines <= lines - 1;
		end else if (wrreq && !full_) begin
			lines <= lines + 1;
		end

		// pointer and mem update
		if (rdreq && !empty_) begin
			// only do this if buffer_elems about to be 0
			if (buffer_elems == 1) begin
				rdline <= rdline + 1;
				if (lines != 1) begin
					// update rdptr with nbase with each new line
					rdptr <= 0;
					// also update buffer_elems
					buffer_elems <= last_ && last_rdline == rdline1 ? last_bounds : MAX_ELEMS;
					// reset last signals
					if (last_ && last_rdline == rdline1) begin
						last_ <= 0;
						last_rdline <= 0;
					end
				end
			end
			// normal case, read out data and update ptr
			else begin
				buffer_elems <= buffer_elems - 1;
				rdptr <= rdptr + 1;
			end
			/* $display("%0d: buffer[%0d][%0d] = %x", WIDTH, rdline, rdptr, buffer[rdline][rdptr]); */
		end
		if (wrreq && !full_) begin
			wrline <= wrline + 1;

			if (last) begin
				last_ <= 1;
				last_rdline <= wrline;
				last_bounds <= bounds;
				$display("%0d: setting last_rdline = %0d, last_bounds = %0d", WIDTH, wrline, bounds);
			end

			// no lines, need to set initial values
			if (empty_ || (rdreq && lines == 1 && buffer_elems == 1)) begin
				rdptr <= 0;
				buffer_elems <= last ? bounds : MAX_ELEMS;
			end
			/* $display("%0d: buffer[%0d] = %b", WIDTH, wrline, wdata); */
		end
	end
end
endmodule

 
