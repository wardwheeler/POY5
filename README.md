# POY5
Phylogenetic analysis program for general data inclusing unaligned sequence data
Instruction to compile poy5.1.2a
Ward Wheeler 
Sept. 4, 2018

Citation: 
Wheeler, W. C., N. Lucaroni, L. Hong, L. M. Crowley, and A. Varón.  2015.  POY version 5: Phylogenetic analysis using dynamic homologies under multiple optimality criteria.  Cladistics 31:189-196.


Due to OCAML compiler changes only Ocaml 4.01.0 will work properly

Additional packages required: 
(for Ubuntu 18.04)
sudo apt-get install lapack
sudo apt-get install gfortran
sudo apt-get install mpi (if you want parallel execution via MPI)
sudo apt-get install zlib1gcd -dev


To compile with OCaml 4.01.0:

install POY package in PATH
navigate to PATH/src
make clean

./configure --enable-large-alphabets --enable-long-sequences --enable-unsafe --enable-likelihood --enable-interface=flat

for parallel add --enable-mpi CC=mpicc

ocamlbuild poy.native

binary in ./_build/poy.native
