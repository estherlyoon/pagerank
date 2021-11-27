#!/usr/bin/env python3

import argparse
import random
import sys
import os
import networkx as nx

""" 
mem_init.hex structure:
	n_vertices | n_edges | vertex map | in-edges map | # out-edges map
	everything is represented as a 64-bit integer (written as 8 hex characters), but this could be easily parameterized
	note: since we're not adding repeat edges, if n_edges is > n_vertices, program will hang. As long as you use fairly more vertices, should be fine, otherwise just run again.
"""

separator = 0

# add some number of edges in range [1, e] for each vertex
# don't add any self-edges or repeat edges
def generate_graph(infile):
	G = nx.DiGraph()
	with open(infile) as f:
		data = f.read().split('\n')
		metadata = data[0].split(' ')
		vertices = int(metadata[2])
		print(f'graph has {vertices} vertices')
		
		G.add_nodes_from(range(vertices))

		for i in range(1, len(data)-1):
			line = data[i].split(' ')
			src = int(line[1])
			dest = int(line[2])
			#print(f'add from {src} to {dest}')
			if src != dest and not G.has_edge(src, dest):
				G.add_edge(src, dest)

# uncomment if you want every vertex to have at least one in-edge
#	for v in G:
#		if len(G.in_edges(v)) == 0:
#			src = random.randrange(vertices)
#			G.add_edge(src, v)

	return G

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
	ieaddr = 16 * G.number_of_nodes()
	print("IEADDR:", str(ieaddr))
	wa0 = ieaddr + 8 * total_inedges
	print("WRITE_ADDR0:", str(wa0))
	print("WRITE_ADDR1:", str(wa0 + 8 * G.number_of_nodes()))

def main():
	parser = argparse.ArgumentParser(description='Create graph representation file')
	parser.add_argument('-f', '--filename', type=str,
							help='name of dimacs file to process')

	args = parser.parse_args()

	G = generate_graph(args.filename)

	write_gf(G)

if __name__ == "__main__":
	main()
