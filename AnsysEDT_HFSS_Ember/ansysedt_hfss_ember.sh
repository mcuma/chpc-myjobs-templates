#!/bin/bash
#SBATCH --time=1:00:00 # walltime, abbreviated by -t
#SBATCH --nodes=2      # number of cluster nodes, abbreviated by -N
#SBATCH -o slurm-%j.out-%N # name of the stdout, using the job number (%j) and the first node (%N)
#SBATCH --ntasks=4    # number of MPI tasks, abbreviated by -n
# additional information for allocated clusters
#SBATCH --account=owner-guest     # account - abbreviated by -A
#SBATCH --partition=ember-guest  # partition, abbreviated by -p

set echo
module load ansysedt/17.0

# specify work directory and input file names
export WORKDIR=`pwd`
export INPUTNAME="tune_coax_fed_patch.aedt"
export INPUTDIR="$ANSYSEDT_ROOT/Linux64/Examples/HFSS/Antennas"

# cd to the work directory
cp $INPUTDIR/$INPUTNAME $WORKDIR
cd $WORKDIR

# figure number of cores per task
# find number of tasks per node
TPN=`echo $SLURM_TASKS_PER_NODE | cut -f 1 -d \(`
# find number of CPU cores per node
PPN=`echo $SLURM_JOB_CPUS_PER_NODE | cut -f 1 -d \(`
#THREADS=$((PPN/TPN))
THREADS=$((PPN))


# figure out what nodes we run on
srun hostname | sort -u > nodefile

# distributed parallel run setup
# can't start ansoft RSM in its default location since it can't write to the log file owned by hpcapps, despite specifying the logfile option
#/uufs/chpc.utah.edu/sys/installdir/hfss/rsm/Linux/ansoftrsmservice start -logfile ~/ansoftrsmservice.log
# instead copy the directory
cp -r $ANSYSEDT_ROOT/../rsm/Linux64 .
# and loop over all nodes in the job to start the service
for NODE in `cat nodefile`; do
  # start the RSM service
  ssh $NODE $WORKDIR/Linux64/ansoftrsmservice start
  # register engines with RSM (otherwise it'll complain that it can't find it)
  ssh $NODE $ANSYSEDT_ROOT/Linux64/RegisterEnginesWithRSM.pl add
done

# create list of hosts:tasks:cores
export ABQHOSTS=""
a=1
for NODE in `cat nodefile`; do
  if (( $a == 1 )); then
    export ABQHOSTS="${ABQHOSTS}${NODE}:${TPN}:${THREADS}"
  else
    export ABQHOSTS="${ABQHOSTS},${NODE}:${TPN}:${THREADS}"
  fi
  let a=$a+1
done

echo $ABQHOSTS

# create batch options file
# this is necessary for correct license type
export OptFile="batch.cfg"
echo \$begin \'Config\' > ${OptFile}
echo \'HFSS/NumCoresPerDistributedTask\'=${THREADS} >> ${OptFile}
echo \'HFSS/HPCLicenseType\'=\'Pool\' >> ${OptFile}
echo \'HFSS/SolveAdaptiveOnly\'=0 >> ${OptFile}
echo \'HFSS/MPIVendor\'= \'Intel\' >> ${OptFile}
echo \$end \'Config\' >> ${OptFile}

ansysedt -ng -batchsolve -distributed -machinelist list="${ABQHOSTS}" -batchoptions $OptFile $INPUTNAME 

# stop the RSM service when done
for NODE in `cat nodefile`; do
  ssh $NODE $WORKDIR/Linux64/ansoftrsmservice stop
done
# remove directory with the RSM files
rm -rf $WORKDIR/Linux64
