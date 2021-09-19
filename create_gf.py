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
	with open('mem_init.hex', 'w') as f:
		f.write(int_to_bytestring(G.number_of_nodes()))	
		f.write(int_to_bytestring(G.number_of_edges()))	
		separator += 2
		# vertex array
		for node in G:
			f.write(int_to_bytestring(offset))
			offset += len(G.in_edges(node))
			update_separator(f)
		# in-edge array
		for node in G:
			for in_edge in G.in_edges(node):
				f.write(int_to_bytestring(in_edge[0]))
				update_separator(f)
		# number of out-edges array
		for node in G:
			f.write(int_to_bytestring(len(G.out_edges(node))))
			update_separator(f)

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
