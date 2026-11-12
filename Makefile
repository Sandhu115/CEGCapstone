VHDL_FILES = trng_sim_model.vhd switch.vhd n_bit_register.vhd mux2to1_nbit.vhd permutation_network.vhd double_permutation_network.vhd tb_double_permutation_network.vhd
TB_TOP = tb_double_permutation_network

all: compile run view

compile:
	ghdl -a --std=08 $(VHDL_FILES)
	ghdl -e --std=08 $(TB_TOP)

run:
	ghdl -r --std=08 $(TB_TOP) --wave=dump.ghw --stop-time=10us

view:
	gtkwave dump.ghw &