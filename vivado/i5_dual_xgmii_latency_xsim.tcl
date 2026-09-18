if {[llength $argv] != 1} {
    error "usage: vivado -mode batch -source vivado/i5_dual_xgmii_latency_xsim.tcl -tclargs <market_phase_ps>"
}
set phase_ps [lindex $argv 0]
if {![string is integer -strict $phase_ps] || $phase_ps < 0 || $phase_ps >= 6400} {
    error {market_phase_ps must be an integer in [0, 6399]}
}

set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir ".."]]
set hft_root [file join $root "deps" "hft-full-system-fpga"]
if {[info exists ::env(HFT_RMIC_OUT_DIR)] && $::env(HFT_RMIC_OUT_DIR) ne ""} {
    set out_dir [file normalize $::env(HFT_RMIC_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $root "build" "runs" "i5-dual-xgmii-xsim-manual"]]
}
file mkdir $out_dir
set part_name "xcu50-fsvh2104-2-e"

proc load_filelist {root_dir filelist_path src_var inc_var} {
    upvar $src_var src_files
    upvar $inc_var include_dirs
    set fh [open $filelist_path r]
    foreach line [split [read $fh] "\n"] {
        set item [string trim [string map [list \uFEFF ""] $line]]
        if {$item eq "" || [string match "#*" $item]} { continue }
        if {[string match "+incdir+*" $item]} {
            lappend include_dirs [file normalize [file join $root_dir [string range $item 8 end]]]
        } elseif {[string match "-f *" $item]} {
            load_filelist $root_dir [file join $root_dir [string trim [string range $item 3 end]]] src_files include_dirs
        } elseif {![string match "tb/*" $item]} {
            lappend src_files [file normalize [file join $root_dir $item]]
        }
    }
    close $fh
}

set src_files {}
set include_dirs [list [file join $root "rtl" "include"] [file join $root "deps" "RMIC" "rtl"]]
load_filelist $hft_root [file join $hft_root "filelists" "dual_xgmii_full_system_sim.f"] src_files include_dirs
set integration_sources [list \
    [file join $root "deps" "RMIC" "rtl" "amu_bank_ram.sv"] \
    [file join $root "deps" "RMIC" "rtl" "amu_banked_double_hash_v2.sv"] \
    [file join $root "rtl" "adapters" "configurable_exact_map.sv"] \
    [file join $root "rtl" "adapters" "hft_order_to_rmic.sv"] \
    [file join $root "rtl" "adapters" "hft_tmp_exec_metadata_tap_v2.sv"] \
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
    [file join $root "rtl" "integration" "hft_rmic_committed_exec_event_adapter_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_exec_commit_fifo_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_spec_order_dedupe_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_cached_exact_map_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_order_ingress_slice_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_xgmii_tx_encoder_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_rx_order_book_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_round_chip_app_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_xgmii_network_layer_e2e_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_dual_xgmii_full_system_top_v1.sv"]]
set src_files [lsort -unique [concat $src_files $integration_sources]]
set include_dirs [lsort -unique [concat $include_dirs [list [file join $hft_root "rtl" "common" "include"] [file join $hft_root "rtl" "network" "xgmii"]]]]
set tb_file [file join $root "tb" "tb_hft_rmic_dual_xgmii_full_system.sv"]
foreach f [concat $src_files [list $tb_file]] { if {![file exists $f]} { error "required I5 XSim source missing: $f" } }

set proj_dir [file join $out_dir "project"]
create_project i5_latency_phase_${phase_ps}_xsim $proj_dir -part $part_name -force
set_property source_mgmt_mode None [current_project]
add_files -norecurse -fileset sources_1 $src_files
add_files -norecurse -fileset sim_1 $tb_file
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property include_dirs $include_dirs [get_filesets sim_1]
set_property verilog_define {AMU_BEHAVIORAL_RAM HFT_RMIC_BEHAVIORAL_RAM} [get_filesets sources_1]
set_property verilog_define {AMU_BEHAVIORAL_RAM HFT_RMIC_BEHAVIORAL_RAM} [get_filesets sim_1]
set_property top tb_hft_rmic_dual_xgmii_full_system [get_filesets sim_1]
set_property generic "SC5_LATENCY=1 SC5_MARKET_PHASE_PS=$phase_ps" [get_filesets sim_1]
set_property xsim.simulate.runtime {0ns} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run 1200us
close_sim

set pass_seen 0
set fail_seen 0
set sample_seen 0
foreach f [glob -nocomplain [file join $proj_dir "*.log"] [file join $proj_dir "*" "*.log"] [file join $proj_dir "*" "*" "*.log"] [file join $proj_dir "*" "*" "*" "*.log"] [file join $proj_dir "*" "*" "*" "*" "*.log"]] {
    set fh [open $f r]; set text [read $fh]; close $fh
    if {[string first "TB_HFT_RMIC_DUAL_XGMII_SC5_LATENCY PASS" $text] >= 0} { set pass_seen 1 }
    if {[string first "SC5_DUAL_LATENCY_SAMPLE phase_ps=$phase_ps" $text] >= 0} { set sample_seen 1 }
    if {[string first "TEST_FAIL" $text] >= 0} { set fail_seen 1 }
}
if {!$pass_seen || !$sample_seen || $fail_seen} {
    error "I5 latency phase $phase_ps did not produce a clean sample"
}
puts "HFT_RMIC_I5_LATENCY_PHASE_PASS phase_ps=$phase_ps"
puts "MILESTONE=I5_LATENCY_RECOVERY_MEASUREMENT"
quit
