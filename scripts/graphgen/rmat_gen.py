#!/usr/bin/env python3

import argparse
import snap
import random
import sys
import os 

separator = 0

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
	with open('mem_init.hex', 'w') as f:
		# vertex array
		for v in G.Nodes():
			node = v.GetId()
			# write offset into ie vertices array
			f.write(int_to_bytestring(offset))
			offset += v.GetInDeg()
			update_separator(f)
			# write number of out-edges this vertex has
			f.write(int_to_bytestring(v.GetOutDeg()))
			update_separator(f)
		# 0-pad the rest
		while separator % 8 != 0:
			f.write(int_to_bytestring(0))
			update_separator(f)
		# in-edge array
		for node in G.Nodes():
			random_edges = []
			n_ie = node.GetInDeg()
			#print("in-edges:", n_ie)
			for i in range(n_ie):
				in_edge = node.GetInNId(i)
				random_edges.append(in_edge)
			random.shuffle(random_edges)
			for in_edge in random_edges:
				f.write(int_to_bytestring(in_edge))
				update_separator(f)
			#print("random edges:", len(random_edges))
			assert(node.GetInDeg() == len(random_edges))
			total_inedges += len(random_edges)
		# fill writespace with 0s
		for _ in range(2*G.GetNodes()):
			f.write(int_to_bytestring(0))
			update_separator(f)
		# 0-pad the rest
		while separator % 8 != 0:
			f.write(int_to_bytestring(0))
			separator += 1
	
	
	print("--- parameters (in decimal) ---")
	print("N_VERT:", G.GetNodes())
	print("N_INEDGES:", total_inedges)
	print("--- potential address parameters ---")
	print("VADDR:", str(0))
	# 8 bytes * 2 * N_VERT
	vbytes = 16 * G.GetNodes()
	ieaddr = vbytes if (vbytes % 64 == 0) else vbytes + (64 - vbytes % 64)
	print("IEADDR:", str(ieaddr))
	wa0 = ieaddr + 8 * total_inedges
	print("WRITE_ADDR0:", str(wa0))
	print("WRITE_ADDR1:", str(wa0 + 8 * G.GetNodes()))
    
def main():
	parser = argparse.ArgumentParser(description='Create graph representation file')
	parser.add_argument('-v', '--vertices', type=int)
	parser.add_argument('-e', '--edges', type=int)

	args = parser.parse_args()

	Rnd = snap.TRnd()
	G = snap.GenRMat(args.vertices, args.edges, .6, .1, .15, Rnd)

	#for EI in G.Edges():
	#	print("edge: (%d, %d)" % (EI.GetSrcNId(), EI.GetDstNId()))

	write_gf(G)

if __name__ == "__main__":
	main()
