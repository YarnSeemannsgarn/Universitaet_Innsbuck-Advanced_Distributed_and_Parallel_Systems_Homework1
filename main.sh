#!/bin/sh

PWD="$PWD"
BIN_DIR=${PWD}/bin
INPUT_DIR=${PWD}/inputdata
JOB_DIR=${PWD}/jobs
SEQ_DIR=${PWD}/results/sequential
PAR_DIR=${PWD}/results/parallel
mkdir -p $SEQ_DIR
mkdir -p $PAR_DIR
headline="***************"

# Start timer
START=$(date +%s.%N)

# Task 1: Execute job_task1 in current directory
echo "$headline TASK 1 $headline"
echo "Execute job_task1 on one processor to generate all png files"
qsub -N job_task1 -cwd -e ${SEQ_DIR}/ -o ${SEQ_DIR}/ -v BIN_DIR=${BIN_DIR},INPUT_DIR=${INPUT_DIR} ${JOB_DIR}/job_task1.pbs

## Task 2: Merge pngs to gif
echo
echo "$headline TASK 2 $headline"
echo "Merge all png files, when all pngs are generated"
qsub -N job_task2 -cwd  -e ${SEQ_DIR}/ -o ${SEQ_DIR}/ -sync y -hold_jid job_task1 -v BIN_DIR=${BIN_DIR} ${JOB_DIR}/job_task2.pbs

## Task 3: Measure the execution time for task 1 and 2
END=$(date +%s.%N)
Tseq=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
echo
echo "$headline TASK 3 $headline"
echo "The sequential execution time Tseq was $Tseq seconds"

# Move files to SEQ_DIR
echo "Move pngs and gif to $SEQ_DIR"
mv ${PWD}/*.png ${PWD}/*.gif ${SEQ_DIR}/

# Task 4: Get frame and processor numbers
# Read .ini file to get frame numbers
while read line
do
    if [[ $line == Initial_Frame* ]] || [[ $line == Final_Frame* ]] ;
    then
	equal_pos=`expr index $line =`
	length=`expr length $line`
	frame_number=${line:equal_pos:length}
	
	if [[ $line == Initial_Frame* ]] ;
	then
	    INITIAL_FRAME=$frame_number
	else
	    FINAL_FRAME=$frame_number
	fi
    fi
done < ${INPUT_DIR}/scherk.ini

# M = number of frames
M=$((FINAL_FRAME - INITIAL_FRAME + 1))
echo
echo "$headline TASK 4 and 5 $headline"
echo "$M frames will be rendered in parallel"

# Get available processors
# N = processors in grid
N=0
qhost_output=$(qhost)
while read line
do
    node_processors=`echo $line | cut -d' ' -f3`
    if [[ $node_processors =~ ^[[:digit:]]+$ ]] && [[ $node_processors -gt 0 ]] ;
    then
	N=$((N + node_processors))
    fi
done <<< "$qhost_output"
echo "The grid has $N processors in total"

# Task 4 & 5: Split frames to processors
START=$(date +%s.%N)

if [[ $N -gt $M ]] ;
then
    echo "There are more processors than frames, so only $M processors will be used"
    USED_PROCESSORS=$M
else
    USED_PROCESSORS=$N
fi

subset_start_frame=1
subsets_per_processor=$(( M/N ))
modulo=`expr $M % $N`
parallel_job_names=""
echo "Execute job_task5 on $USED_PROCESSORS processors to generate all png files"
for (( i=1; i<=$USED_PROCESSORS; i++ ))
do
    subset_end_frame=$((subset_start_frame + subsets_per_processor - 1))
    if [[ $i -le $modulo ]]
    then
	subset_end_frame=$((subset_end_frame + 1))
    fi

    job_name=job_task5_part$i
    qsub -N $job_name -cwd -e ${PAR_DIR}/ -o ${PAR_DIR}/ -v BIN_DIR=${BIN_DIR},INPUT_DIR=${INPUT_DIR},SF=${subset_start_frame},EF=${subset_end_frame} ${JOB_DIR}/job_task5.pbs
    subset_start_frame=$((subset_end_frame + 1))
    parallel_job_names="${parallel_job_names},${job_name}"
done

# Use job_task2 to merge files
echo "Merge all png files, when all pngs are generated"
qsub -N job_task5_merge -cwd -sync y -hold_jid ${parallel_job_names} -e ${PAR_DIR}/ -o ${PAR_DIR}/ -v BIN_DIR=${BIN_DIR} ${JOB_DIR}/job_task2.pbs

# Task 6: Measure the execution time for step 5
END=$(date +%s.%N)
Tpar=$(echo "$END - $START" | bc | awk '{printf "%f", $0}')
echo
echo "$headline TASK 6 $headline"
echo "The parallel execution time Tpar was $Tpar seconds"

# Move files to PAR_DIR
echo "Move pngs and gif to $PAR_DIR"
mv ${PWD}/*.png ${PWD}/*.gif ${PAR_DIR}/

# Task 7: Calculate speedup
# S = speedup
S=$(echo "scale=9;$Tseq / $Tpar" | bc | awk '{printf "%f", $0}')
echo
echo "$headline TASK 7 $headline"
echo "The speedup was $S"

# Task 8: Calculate efficency
# E = efficency
E=$(echo "scale=9;$S / $N" | bc | awk '{printf "%f", $0}')
echo
echo "$headline TASK 8 $headline"
echo "The efficency was $E"
