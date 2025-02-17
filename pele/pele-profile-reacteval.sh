#!/bin/bash -l

set -e

cmd() {
  echo "+ $@"
  eval "$@"
}

# Generate Pele build script
cat >build.sh <<'EOF'
#!/bin/bash -l

#SBATCH --job-name=pele-test-case-build-gpu
#SBATCH --output %x.o%j
#SBATCH --account=hpacf
#SBATCH --time=1:00:00
#SBATCH --partition=gpu-h100s
#SBATCH --nodes=1
#SBATCH --gpus-per-node=1
#SBATCH --ntasks-per-node=32
#SBATCH --mem=64GB

set -e
cmd() {
  echo "+ $@"
  eval "$@"
}

cmd "module load PrgEnv-gnu"
cmd "module load cray-python"
cmd "module load cuda"
cmd "module load craype-x86-milan"
cmd "module list"
cmd "git clone --recursive https://github.com/AMReX-Combustion/PeleLMeX.git" || true
cmd "cp /scratch/jrood/pele/ReactEval_latest.tar.gz PeleLMeX/Submodules/PelePhysics/Testing/Exec/"
cmd "cd PeleLMeX/Submodules/PelePhysics/Testing/Exec/"
cmd "tar xf ReactEval_latest.tar.gz"
cmd "cd ReactEval_latest"
cmd "make TPLrealclean; make DIM=3 COMP=gnu USE_CUDA=TRUE USE_MPI=TRUE TINY_PROFILE=TRUE TPL; make realclean; nice make DIM=3 COMP=gnu USE_CUDA=TRUE USE_MPI=TRUE TINY_PROFILE=TRUE -j32"
EOF

echo "sbatch build.sh"
BUILDJOBID=$(sbatch --parsable build.sh)
cmd "rm build.sh"

# Generate Pele run script
cat >run.sh <<'EOF'
#!/bin/bash -l

#SBATCH --job-name=pele-test-case-run-gpu
#SBATCH --output %x.o%j
#SBATCH --account=hpacf
#SBATCH --time=1:00:00
#SBATCH --partition=gpu-h100s
#SBATCH --nodes=1
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=128
#SBATCH --exclusive
#SBATCH --mem=0

set -e
cmd() {
  echo "+ $@"
  eval "$@"
}

MYCWD=${PWD}
NTASKS_PER_NODE=4
RANKS=$(( ${NTASKS_PER_NODE}*${SLURM_JOB_NUM_NODES} ))

cmd "module load PrgEnv-gnu"
cmd "module load cray-python"
cmd "module load cuda"
cmd "module load craype-x86-milan"
cmd "module load hpctoolkit/2024.01.1-cray-mpich-gcc"
cmd "module list"
cmd "cd ${MYCWD}/PeleLMeX/Submodules/PelePhysics/Testing/Exec/ReactEval_latest"

cmd "export MPICH_OFI_SKIP_NIC_SYMMETRY_TEST=1"
cmd "export MPICH_GPU_SUPPORT_ENABLED=0"
cmd "srun -N ${SLURM_JOB_NUM_NODES} -n ${RANKS} --ntasks-per-node=${NTASKS_PER_NODE} --gpus-per-node=4 --gpu-bind=closest hpcrun -o profile-gpu -t -e CPUTIME -e gpu=nvidia ./Pele3d.gnu.TPROF.MPI.CUDA.ex inputs.3d_1dArray_failedcase amr.checkpoint_files_output=0 amr.plot_files_output=0 amr.plot_int=-1 amr.check_int=-1 cvode.solve_type=GMRES amrex.abort_on_out_of_gpu_memory=1 amrex.the_arena_is_managed=0 amr.blocking_factor=16 amr.max_grid_size=128 amrex.use_profiler_syncs=0 amrex.async_out=0 amrex.use_gpu_aware_mpi=0"
cmd "hpcstruct profile-gpu"
cmd "hpcprof -o profile-gpu-db profile-gpu"
EOF

cmd "sbatch --dependency=afterok:${BUILDJOBID} run.sh"
cmd "rm run.sh"

#To view results: ssh -Y kl5.hpc.nrel.gov, then `module load hpctoolkit/2024.01.1-cray-mpich-gcc && hpcviewer &` and then browse to profile-gpu-db and open that directory
