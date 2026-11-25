create_project -in_memory -part xc7a100tcsg324-1
read_edif nexys_top.edif
read_xdc nexys_a7.xdc
link_design -top nexys_top -part xc7a100tcsg324-1
opt_design
place_design
route_design
report_utilization -file util.txt
report_timing_summary -file timing.txt
report_timing -max_paths 1 -file worst_path.txt
write_bitstream -force nexys_top.bit
