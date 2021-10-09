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
def generate_graph(vertices, edges):
	G = nx.DiGraph()
	G.add_nodes_from(range(vertices))

	for v in range(vertices):
		n_edges = random.randrange(1, edges+1)
		added_edges = 0
		while added_edges != n_edges:
			dest = random.randrange(vertices)
			if v != dest and not G.has_edge(v, dest):
				G.add_edge(v, dest)
				added_edges += 1

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
	with open('test.hex', 'w') as f:
		# vertex array
		for node in G:
			# write offset for in-edge array
			f.write(int_to_bytestring(len(G.in_edges(node))))
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
			total_inedges += len(random_edges)
		# 0-pad the rest
		while separator % 8 != 0:
			f.write(int_to_bytestring(0));
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
	parser.add_argument('-v', '--vertices', type=int, nargs=1,
							help='number of vertices in graph')
	parser.add_argument('-e', '--edges', type=int, nargs=1,
							help='max edges per node')

	args = parser.parse_args()
	vertices = args.vertices[0]
	edges = args.edges[0]

	G = generate_graph(vertices, edges)

	write_gf(G)

if __name__ == "__main__":
	main()
