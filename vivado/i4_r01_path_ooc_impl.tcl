set script_dir [file dirname [info script]]
set root [file normalize [file join $script_dir ".."]]

if {[info exists ::env(HFT_RMIC_OUT_DIR)] && $::env(HFT_RMIC_OUT_DIR) ne ""} {
    set out_dir [file normalize $::env(HFT_RMIC_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $root "build" "runs" "i4-r01-path-ooc-manual"]]
}
file mkdir $out_dir

set part "xcu50-fsvh2104-2-e"
set top "hft_rmic_r01_path_v1"
set incdirs [list \
    [file join $root "rtl" "include"] \
    [file join $root "deps" "RMIC" "rtl"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "common" "include"]]

set headers [list \
    [file join $root "rtl" "include" "hft_rmic_accounting_defs.svh"] \
    [file join $root "rtl" "include" "hft_rmic_contract.svh"] \
    [file join $root "rtl" "include" "hft_rmic_policy_defs.svh"] \
    [file join $root "rtl" "include" "taifex_tmp_v2187_defs.svh"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "common" "include" "round_chip_defs.vh"]]

set sources [list \
    [file join $root "deps" "RMIC" "rtl" "amu_bank_ram.sv"] \
    [file join $root "deps" "RMIC" "rtl" "amu_banked_double_hash_v2.sv"] \
    [file join $root "rtl" "adapters" "configurable_exact_map.sv"] \
    [file join $root "rtl" "adapters" "hft_order_to_rmic.sv"] \
    [file join $root "rtl" "policy" "hft_rmic_policy_gate.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_futures_transition_v1.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_state_ram.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_futures_state_manager_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_futures_order_store_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_cl2ex_admission_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_order_gate_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_committed_execution_bridge_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_shared_core_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_dual_order_source_v1.sv"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "encoder" "payload" "order_arbiter.v"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "encoder" "payload" "order_request_fifo.v"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "encoder" "tmp" "tmp_r01_fast_stream_encoder.v"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "encoder" "tmp" "tmp_r05_fast_stream_encoder.v"] \
    [file join $root "deps" "hft-full-system-fpga" "rtl" "encoder" "session" "financial_protocol_encoder.v"] \
    [file join $root "rtl" "integration" "hft_rmic_r01_path_v1.sv"]]

foreach f [concat $headers $sources] {
    if {![file exists $f]} { error "required I4 source missing: $f" }
}

create_project -in_memory hft_rmic_i4_r01_ooc -part $part
add_files -norecurse $headers
add_files -norecurse $sources
set_property file_type {Verilog Header} [get_files *.svh]
set_property file_type {Verilog Header} [get_files *.vh]
set_property file_type SystemVerilog [get_files *.sv]
set_property include_dirs $incdirs [current_fileset]
set_property top $top [current_fileset]

if {[catch {auto_detect_xpm} xpm_err]} {
    error "auto_detect_xpm failed: $xpm_err"
}
set xpm_libs "auto_detect_xpm completed"
if {![catch {set detected_xpm [get_property XPM_LIBRARIES [current_project]]}]} {
    if {$detected_xpm ne ""} { set xpm_libs $detected_xpm }
}
puts "HFT_RMIC_XPM_LIBRARIES=$xpm_libs"

synth_design -top $top -part $part -flatten_hierarchy rebuilt -mode out_of_context
create_clock -name hft_rmic_clk -period 6.400 [get_ports clk]

report_utilization -hierarchical -file [file join $out_dir "utilization_synth.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_synth.rpt"]
report_timing_summary -delay_type max -max_paths 30 -file [file join $out_dir "timing_summary_synth.rpt"]
write_checkpoint -force [file join $out_dir "i4_r01_path_ooc_synth.dcp"]

set synth_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $synth_paths] > 0} {
    puts "HFT_RMIC_I4_SYNTH_WNS=[get_property SLACK [lindex $synth_paths 0]]"
}

set bram36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E2}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E2}]]
puts "HFT_RMIC_I4_BRAM36_COUNT=$bram36_count"
puts "HFT_RMIC_I4_BRAM18_COUNT=$bram18_count"
if {[expr {$bram36_count + $bram18_count}] == 0} {
    error "I4 R01 OOC block-RAM gate failed: no RAMB36E2/RAMB18E2 cells after synthesis"
}

opt_design
place_design
report_utilization -hierarchical -file [file join $out_dir "utilization_placed.rpt"]
report_timing_summary -delay_type max -max_paths 30 -file [file join $out_dir "timing_summary_placed.rpt"]
write_checkpoint -force [file join $out_dir "i4_r01_path_ooc_placed.dcp"]
set placed_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $placed_paths] > 0} {
    puts "HFT_RMIC_I4_PLACED_WNS=[get_property SLACK [lindex $placed_paths 0]]"
}

phys_opt_design
route_design

report_utilization -hierarchical -file [file join $out_dir "utilization_routed.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_routed.rpt"]
report_timing_summary -delay_type max -max_paths 50 -file [file join $out_dir "timing_summary_routed.rpt"]
report_timing -from [get_clocks hft_rmic_clk] -to [get_clocks hft_rmic_clk] -delay_type max -max_paths 50 -nworst 10 -file [file join $out_dir "timing_reg2reg.rpt"]
report_route_status -file [file join $out_dir "route_status.rpt"]
report_drc -file [file join $out_dir "drc_routed.rpt"]
report_power -file [file join $out_dir "power_routed.rpt"]
report_design_analysis -timing -setup -max_paths 20 -file [file join $out_dir "design_analysis_timing.rpt"]
write_checkpoint -force [file join $out_dir "i4_r01_path_ooc_routed.dcp"]

set worst_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_paths] == 0} {
    error "I4 R01 OOC timing gate failed: no setup timing path found"
}
set routed_wns [get_property SLACK [lindex $worst_paths 0]]
puts "HFT_RMIC_I4_ROUTED_WNS=$routed_wns"
if {$routed_wns < 0.0} {
    error "I4 R01 OOC routed timing failed: WNS=$routed_wns ns"
}

puts "HFT_RMIC_I4_R01_PATH_OOC_IMPL_DONE"
puts "MILESTONE=I4_RISK_TO_FROZEN_R01_OOC"
puts "PART=$part"
puts "CLOCK_PERIOD_NS=6.400"
puts "OUT_DIR=$out_dir"
