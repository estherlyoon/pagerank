#!/bin/bash

AGFI=agfi-000000000000

N_VERT=$0
N_IE=$1
IE_ADDR=$2
WADDR0=$3
WADDR1=$4
ROUNDS=$5
BIN=$6

for i in {0..3} do
	sudo cp ${BIN} /mnt/nvme0/file$i.bin
done

loadfpga $AGFI

sudo ./vmt_test > ${N_VERT}v_${N_IE}e.pages &
vmt_pid=$!
sleep 2
sudo ./pr_test $N_VERT $N_IE $IE_ADDR $WADDR0 $WADDR1 $ROUNDS

kill -9 $vmt_pid
