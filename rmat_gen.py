#!/usr/bin/env python3

import argparse
import snap

def main():
	parser = argparse.ArgumentParser(description='Create graph representation file')
	parser.add_argument('-v', '--vertices', type=int)
	parser.add_argument('-e', '--edges', type=int)

	args = parser.parse_args()

	Rnd = snap.TRnd()
	Graph = snap.GenRMat(args.vertices, args.edges, .6, .1, .15, Rnd)

	for EI in Graph.Edges():
		    print("edge: (%d, %d)" % (EI.GetSrcNId(), EI.GetDstNId()))
	#G = generate_graph(args.filename)

def int_to_bytestring(n, minlen=0):
	if n > 0:
		arr = []
		while n:
			n, rem = n >> 8, n & 0xff
			arr.append(rem)
		b = bytearray(reversed(arr))
	elif n == 0:
		b = bytearray(b'\x00')
	else:
		raise ValueError('Only non-negative values supported')

	if minlen > 0 and len(b) < minlen: # zero padding needed?
		b = (minlen-len(b)) * '\x00' + b
	return '{:016X}'.format(int(b.hex(), 16))

def update_separator(f):
	global separator
	separator += 1
	if separator % 8 == 0:
		f.write("\n")

def write_gf(G):
	global separator
	offset = 0
	total_inedges = 0
	max_inedges = 0
	with open('mem_init.hex', 'w') as f:
		# vertex array
		for node in G:
			# write offset into ie vertices array
			f.write(int_to_bytestring(offset))
			offset += len(G.in_edges(node))
			update_separator(f)
			# write number of out-edges this vertex has
			f.write(int_to_bytestring(len(G.out_edges(node))))
			update_separator(f)
		# 0-pad the rest
		while separator % 8 != 0:
			f.write(int_to_bytestring(0))
			update_separator(f)
		# in-edge array
		for node in G:
			random_edges = []
			for in_edge in G.in_edges(node):
				random_edges.append(in_edge[0])
			random.shuffle(random_edges)
			for in_edge in random_edges:
				f.write(int_to_bytestring(in_edge))
				update_separator(f)
			assert(len(G.in_edges(node)) == len(random_edges))
			total_inedges += len(random_edges)
			if len(random_edges) > max_inedges:
				max_inedges = len(random_edges)
		# fill writespace with 0s
		for _ in range(2*G.number_of_nodes()):
			f.write(int_to_bytestring(0))
			update_separator(f)
		# 0-pad the rest
		while separator % 8 != 0:
			f.write(int_to_bytestring(0))
			separator += 1
	
	
	print("--- parameters (in decimal) ---")
	print("N_VERT:", G.number_of_nodes())
	print("N_INEDGES:", total_inedges)
	print("--- potential address parameters ---")
	print("VADDR:", str(0))
	# 8 bytes * 2 * N_VERT
	vbytes = 16 * G.number_of_nodes()
	ieaddr = vbytes if (vbytes % 64 == 0) else vbytes + (64 - vbytes % 64)
	print("IEADDR:", str(ieaddr))
	wa0 = ieaddr + 8 * total_inedges
	print("WRITE_ADDR0:", str(wa0))
	print("WRITE_ADDR1:", str(wa0 + 8 * G.number_of_nodes()))

def main():
	parser = argparse.ArgumentParser(description='Create graph representation file')
	parser.add_argument('-v', '--vertices', type=int,
							help='number of vertices in graph')
	parser.add_argument('-e', '--edges', type=int,
							help='max edges per node')

	args = parser.parse_args()
	vertices = args.vertices
	edges = args.edges

	G = generate_graph(vertices, edges)

	write_gf(G)

if __name__ == "__main__":
	main()
