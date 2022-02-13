#!/usr/bin/env python3

import argparse
import os
import subprocess
import json
import time

def main():
	parser = argparse.ArgumentParser(description='Run pagerank benchmarks through parameterized JSONs')
	parser.add_argument('-t', '--type', type=int, default=0)
	parser.add_argument('-f', '--filename', type=str,
							help='.bin graph file to run')
	parser.add_argument('-i', '--iterations', type=int, default=1,
							help='number of iterations to run pagerank accelerator for (add 1 to actual desired number)')
	parser.add_argument('-r', '--runs', type=int, default=1,
							help='total number of runs to record')
	parser.add_argument('-n', '--n_apps', type=int, default=4,
							help='number of apps to run at once')
	parser.add_argument('-c', '--cold_cpu', type=bool, default=False,
							help="calls dropcaches between runs if set")
	parser.add_argument('-d', '--cold_device', type=bool, default=False,
							help="add an iteration, don't account for first iteration (this option is now deprecated and baked into the output of iterations in pagerank.cpp)")
	parser.add_argument('-cp', '--copy_files', type=bool, default=False)

	args = parser.parse_args()
	coldstring = ""
	nruns = args.runs #if not args.cold_device else args.runs+1

	with open('input_data.json', 'r') as params:
	    jfile=params.read()
	data = json.loads(jfile)
	for d in data['files']:
		if os.path.join("data", d['name']) == args.filename:
			n_vert = d['n_vert']
			n_inedges = d['n_inedges']
			ieaddr = d['ieaddr']
			waddr0 = d['waddr0']
			waddr1 = d['waddr1']

	if args.cold_cpu:
		coldstring += "C"
	else:
		coldstring += "W"

	if args.cold_device:
		coldstring += "C"
	else:
		coldstring += "W"

	# start pagerank, pipe to data file
	filename = os.path.splitext(args.filename)[0]
	outfile = f'logs/{os.path.basename(filename)}_{args.iterations}i_{coldstring}_mode{args.type}.data'
	with open(outfile, 'a') as f:
		for run in range(nruns):
			print(f"Run {run} of pagerank")

			if args.copy_files:
				for i in range(args.n_apps):
					os.system(f'sudo cp {args.filename} /mnt/nvme0/file{i}.bin')
				print("Copied files")

			if args.cold_cpu:
				print("Clearing CPU caches")
				with open("/proc/sys/vm/drop_caches", "w") as dc:
				    dc.write("3\n")
				#time.sleep(60)

			# start daemon, pipe to log
			wd = os.getcwd()
			os.chdir("../../daemon")
			daemon = subprocess.run(["sudo", "./start.sh"])
			os.chdir(wd)
			time.sleep(5)

			pr = subprocess.run(["sudo", "./pagerank", str(n_vert), str(n_inedges), str(ieaddr), 
						str(waddr0), str(waddr1), str(args.iterations), str(args.n_apps), str(args.type)], stdout=f)

			os.system("sudo killall daemon")

	print("Done.")

if __name__ == "__main__":
	main()
