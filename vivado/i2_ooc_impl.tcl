set script_dir [file dirname [info script]]
set root [file normalize [file join $script_dir ".."]]

if {[info exists ::env(HFT_RMIC_OUT_DIR)] && $::env(HFT_RMIC_OUT_DIR) ne ""} {
    set out_dir [file normalize $::env(HFT_RMIC_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $root "build" "runs" "i2-ooc-manual"]]
}
file mkdir $out_dir

set part "xcu50-fsvh2104-2-e"
set top "hft_rmic_i2_ooc_top"
set incdirs [list \
    [file join $root "rtl" "include"] \
    [file join $root "deps" "RMIC" "rtl"]]

set sources [list \
    [file join $root "deps" "RMIC" "rtl" "amu_bank_ram.sv"] \
    [file join $root "deps" "RMIC" "rtl" "amu_banked_double_hash_v2.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_futures_accounting_v1.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_state_ram.sv"] \
    [file join $root "rtl" "accounting" "hft_rmic_futures_state_manager_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_futures_order_store_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_committed_execution_bridge_v1.sv"] \
    [file join $root "rtl" "ooc" "hft_rmic_i2_ooc_top.sv"]]

foreach f $sources {
    if {![file exists $f]} {
        error "required source missing: $f"
    }
}

read_verilog -sv -include_dirs $incdirs $sources
auto_detect_xpm
# In Vivado non-project mode auto_detect_xpm is the required operation. Some
# releases expose XPM_LIBRARIES through current_project and some do not; report
# the property when available without making that diagnostic a build blocker.
set xpm_libs "auto_detect_xpm completed"
if {![catch {set detected_xpm [get_property XPM_LIBRARIES [current_project]]}]} {
    if {$detected_xpm ne ""} {
        set xpm_libs $detected_xpm
    }
}
puts "HFT_RMIC_XPM_LIBRARIES=$xpm_libs"

synth_design -top $top -part $part -mode out_of_context
create_clock -name hft_rmic_clk -period 6.400 [get_ports clk]

report_utilization -file [file join $out_dir "utilization_synth.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_synth.rpt"]
report_timing_summary -delay_type max -max_paths 20 -file [file join $out_dir "timing_summary_synth.rpt"]
write_checkpoint -force [file join $out_dir "i2_ooc_synth.dcp"]

set bram36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E2}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E2}]]
puts "HFT_RMIC_I2_BRAM36_COUNT=$bram36_count"
puts "HFT_RMIC_I2_BRAM18_COUNT=$bram18_count"
if {[expr {$bram36_count + $bram18_count}] == 0} {
    error "I2 OOC block-RAM gate failed: no RAMB36E2/RAMB18E2 cells after synthesis"
}

opt_design
place_design
report_utilization -file [file join $out_dir "utilization_placed.rpt"]
report_timing_summary -delay_type max -max_paths 20 -file [file join $out_dir "timing_summary_placed.rpt"]
write_checkpoint -force [file join $out_dir "i2_ooc_placed.dcp"]

phys_opt_design
route_design

report_utilization -file [file join $out_dir "utilization_routed.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_routed.rpt"]
report_timing_summary -delay_type max -max_paths 50 -file [file join $out_dir "timing_summary_routed.rpt"]
report_timing -delay_type max -max_paths 50 -sort_by group -file [file join $out_dir "timing_reg2reg.rpt"]
report_route_status -file [file join $out_dir "route_status.rpt"]
report_drc -file [file join $out_dir "drc_routed.rpt"]
report_power -file [file join $out_dir "power_routed.rpt"]
report_design_analysis -timing -file [file join $out_dir "design_analysis_timing.rpt"]
write_checkpoint -force [file join $out_dir "i2_ooc_routed.dcp"]

set worst_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_paths] == 0} {
    error "I2 OOC timing gate failed: no setup timing path found"
}
set routed_wns [get_property SLACK [lindex $worst_paths 0]]
puts "HFT_RMIC_I2_ROUTED_WNS=$routed_wns"
if {$routed_wns < 0.0} {
    error "I2 OOC routed timing failed: WNS=$routed_wns ns"
}

puts "HFT_RMIC_I2_OOC_IMPL_DONE"
puts "MILESTONE=I2_FUTURES_STATE_AND_EXECUTION_OOC"
puts "PART=$part"
puts "CLOCK_PERIOD_NS=6.400"
puts "OUT_DIR=$out_dir"
