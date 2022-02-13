#!/usr/bin/env python3

import argparse

# this is just a script I used when debugging to check for invalid vpns
def main():
	parser = argparse.ArgumentParser(description='Create graph representation file')
	parser.add_argument('-f', '--filename', type=str,
							help='binary graph file to run')
	args = parser.parse_args()

	count = 0
	with open(args.filename, 'r') as f:
		for line in f:
			print(f"line {count}")
			count += 1
			if 'Tracing' in line:
				continue
			values = line.split(' ')
			vpn = int(values[4].split(',')[0])
			if vpn > 7813:
				print(f"INVALID VPN {vpn} at {count}")

if __name__ == "__main__":
	main()
