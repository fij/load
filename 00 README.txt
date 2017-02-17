load

This is a job manager (load leveler) that I wrote for myself for running many (independent) instances 
(with adjustable user-defined parameter ranges) of a number-crunching program (numerical integration 
of a set of coupled differential equations representing a biochemical reaction network) on a 4000+ 
node cluster.

It needs several other files, and I did also a significant amount of post-processing with further scripts.
Here is an example for how I was running the job manager (I called it "mainController"):


#!/bin/bash

# ----------------- run the simulations -------------
$HOME/work/b/anh/65/anh65--mainController.pl \
\
$HOME/work/b/anh/65/data/all \
$HOME/work/b/anh/20/data/anh20--listOf3nodeNetworks.txt.7z \
anh38--run3nodeSim \
work/b/anh/38 \
\
qb3 \
\
3000 \
1200 \
1200 \
\
$HOME/work/b/anh/38/anh38--parameterFileTemplate.txt \
$HOME/work/b/anh/25/anh25--statusFileTemplate.txt \
$HOME/work/b/anh/25/anh25--inputSignalList.txt \
$HOME/work/b/anh/24/anh24--ifFileAexists--thenMoveToFileB--elseWaitAndTryAgain.pl \
$HOME/work/b/anh/35/anh35--discretizeResponseFunctions.pl \
$HOME/work/b/anh/32/anh32--discrDat--2--fastaSeq.pl \
\
"0.1 10" \
all \
"0_0_0 0_0_1 0_1_0 0_1_1 1_0_0 1_0_1 1_1_0 1_1_1" \
\
3600 \
0.1 \
0.01 \
\
0.5 \
400.0 \
200.0 \
\
100 \
20 \
1 \
\
$HOME/work/b/anh/65/anh65--jobsOtherDirs.txt \
anh65 \
2_x4168 \
\
1.2G \
50M \
20M \
400 \
\
3000 \
\
>>o.all 2>>e.all &
