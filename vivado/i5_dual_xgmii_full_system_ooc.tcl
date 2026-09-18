set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir ".."]]
set hft_root [file join $root "deps" "hft-full-system-fpga"]
if {[info exists ::env(HFT_RMIC_OUT_DIR)] && $::env(HFT_RMIC_OUT_DIR) ne ""} { set out_dir [file normalize $::env(HFT_RMIC_OUT_DIR)] } else { set out_dir [file normalize [file join $root "build" "runs" "i5-dual-xgmii-ooc-manual"]] }
file mkdir $out_dir
set part_name "xcu50-fsvh2104-2-e"
set top_name "hft_rmic_dual_xgmii_full_system_top_v1"

proc load_filelist {root_dir path src_var inc_var} {
    upvar $src_var src_files; upvar $inc_var include_dirs
    set fh [open $path r]
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

set src_files {}; set include_dirs [list [file join $root "rtl" "include"] [file join $root "deps" "RMIC" "rtl"]]
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
    [file join $root "rtl" "integration" "hft_rmic_order_ingress_slice_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_xgmii_tx_encoder_v1.v"] \
    [file join $root "rtl" "integration" "hft_rmic_rx_order_book_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_round_chip_app_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_xgmii_network_layer_e2e_top_v1.sv"] \
    [file join $root "rtl" "integration" "hft_rmic_dual_xgmii_full_system_top_v1.sv"]]
set src_files [lsort -unique [concat $src_files $integration_sources]]
set include_dirs [lsort -unique [concat $include_dirs [list [file join $hft_root "rtl" "common" "include"] [file join $hft_root "rtl" "network" "xgmii"]]]]
foreach f $src_files { if {![file exists $f]} { error "required I5 OOC source missing: $f" } }

create_project -in_memory hft_rmic_i5_dual_xgmii_ooc -part $part_name
set_property source_mgmt_mode None [current_project]
add_files -norecurse -fileset sources_1 $src_files
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property top $top_name [get_filesets sources_1]
if {[catch {auto_detect_xpm} xpm_err]} { error "auto_detect_xpm failed: $xpm_err" }

set xdc_path [file join $out_dir "i5_dual_xgmii_ooc.xdc"]
set xdc [open $xdc_path w]
puts $xdc {create_clock -name market_rx_clk -period 6.400 [get_ports market_rx_clk]}
puts $xdc {create_clock -name trading_clk -period 6.400 [get_ports trading_clk]}
puts $xdc {set_clock_groups -asynchronous -group [get_clocks market_rx_clk] -group [get_clocks trading_clk]}
close $xdc
read_xdc $xdc_path
update_compile_order -fileset sources_1

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt -mode out_of_context
report_utilization -hierarchical -file [file join $out_dir "utilization_synth.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_synth.rpt"]
report_timing_summary -delay_type max -max_paths 50 -file [file join $out_dir "timing_summary_synth.rpt"]
report_cdc -details -file [file join $out_dir "cdc_synth.rpt"]
write_checkpoint -force [file join $out_dir "i5_dual_xgmii_synth.dcp"]
set sp [get_timing_paths -delay_type max -max_paths 1]
if {[llength $sp] > 0} { puts "HFT_RMIC_I5_SYNTH_WNS=[get_property SLACK [lindex $sp 0]]" }
set bram36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E2}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E2}]]
puts "HFT_RMIC_I5_BRAM36_COUNT=$bram36_count"
puts "HFT_RMIC_I5_BRAM18_COUNT=$bram18_count"
if {[expr {$bram36_count + $bram18_count}] == 0} { error "I5 full-system block-RAM gate failed" }

opt_design

# The first real I5 routed run met placement timing (+0.200 ns) but failed
# routing at -0.261 ns with Vivado reporting level-5 global/short congestion.
# Use AMD's congestion-oriented UltraScale flow: spread logic during placement,
# run aggressive post-place physical optimization, then use the alternate CLB
# router so the implementation does not collapse into the same congested
# trading-clock region.
place_design -directive AltSpreadLogic_high
report_utilization -hierarchical -file [file join $out_dir "utilization_placed.rpt"]
report_timing_summary -delay_type max -max_paths 50 -file [file join $out_dir "timing_summary_placed.rpt"]
write_checkpoint -force [file join $out_dir "i5_dual_xgmii_placed.dcp"]
set pp [get_timing_paths -delay_type max -max_paths 1]
if {[llength $pp] > 0} { puts "HFT_RMIC_I5_PLACED_WNS=[get_property SLACK [lindex $pp 0]]" }

phys_opt_design -directive AggressiveExplore
route_design -directive AlternateCLBRouting

# If the congestion-oriented route is still slightly negative, give post-route
# physical optimization the real routed delays.  The 2026-09-19 I5 run reduced
# WNS to only -0.030 ns and the remaining endpoints moved entirely into the
# pinned HFT RX/market paths; the integration risk and TX timing cuts are no
# longer critical.  At that point this is a router-closure problem, not a
# justification for adding another pipeline stage.
set pre_postroute_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $pre_postroute_paths] > 0} {
    set pre_postroute_wns [get_property SLACK [lindex $pre_postroute_paths 0]]
    puts "HFT_RMIC_I5_PRE_POSTROUTE_WNS=$pre_postroute_wns"
    if {$pre_postroute_wns < 0.0} {
        puts "HFT_RMIC_I5_POST_ROUTE_PHYSOPT_TRIGGER=1"
        phys_opt_design -directive Explore
        route_design -directive AlternateCLBRouting -timing_summary
    } else {
        puts "HFT_RMIC_I5_POST_ROUTE_PHYSOPT_TRIGGER=0"
    }
}

# A fully-routed design can be re-entered into route_design; Vivado rip-up and
# re-routes only timing-critical portions.  For the residual tens-of-picoseconds
# miss, use timing-focused router modes before declaring failure.  These passes
# do not change RTL or architectural latency.
set closure_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $closure_paths] > 0} {
    set closure_wns [get_property SLACK [lindex $closure_paths 0]]
    puts "HFT_RMIC_I5_PRE_TIMING_RETRY_WNS=$closure_wns"

    if {$closure_wns < 0.0} {
        puts "HFT_RMIC_I5_ROUTE_RETRY=NoTimingRelaxation"
        route_design -directive NoTimingRelaxation -timing_summary
        set closure_paths [get_timing_paths -delay_type max -max_paths 1]
        set closure_wns [get_property SLACK [lindex $closure_paths 0]]
        puts "HFT_RMIC_I5_AFTER_NOTIMINGRELAX_WNS=$closure_wns"
    }

    if {$closure_wns < 0.0} {
        puts "HFT_RMIC_I5_ROUTE_RETRY=MoreGlobalIterations"
        route_design -directive MoreGlobalIterations -timing_summary
        set closure_paths [get_timing_paths -delay_type max -max_paths 1]
        set closure_wns [get_property SLACK [lindex $closure_paths 0]]
        puts "HFT_RMIC_I5_AFTER_MOREGLOBAL_WNS=$closure_wns"
    }

    if {$closure_wns < 0.0} {
        puts "HFT_RMIC_I5_ROUTE_RETRY=HigherDelayCost"
        route_design -directive HigherDelayCost -timing_summary
        set closure_paths [get_timing_paths -delay_type max -max_paths 1]
        set closure_wns [get_property SLACK [lindex $closure_paths 0]]
        puts "HFT_RMIC_I5_AFTER_HIGHERDELAY_WNS=$closure_wns"
    }
}

report_utilization -hierarchical -file [file join $out_dir "utilization_routed.rpt"]
report_ram_utilization -file [file join $out_dir "ram_utilization_routed.rpt"]
report_timing_summary -delay_type max -max_paths 100 -file [file join $out_dir "timing_summary_routed.rpt"]
report_timing -delay_type max -max_paths 100 -nworst 10 -file [file join $out_dir "timing_worst.rpt"]
report_route_status -file [file join $out_dir "route_status.rpt"]
report_cdc -details -file [file join $out_dir "cdc_routed.rpt"]
report_bus_skew -file [file join $out_dir "bus_skew_routed.rpt"]
report_drc -file [file join $out_dir "drc_routed.rpt"]
report_power -file [file join $out_dir "power_routed.rpt"]
report_design_analysis -timing -setup -max_paths 30 -file [file join $out_dir "design_analysis_timing.rpt"]
write_checkpoint -force [file join $out_dir "i5_dual_xgmii_routed.dcp"]

set worst [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst] == 0} { error "I5 full-system produced no timing path" }
set wns [get_property SLACK [lindex $worst 0]]
puts "HFT_RMIC_I5_ROUTED_WNS=$wns"
if {$wns < 0.0} { error "I5 full-system routed timing failed WNS=$wns" }
puts "HFT_RMIC_I5_DUAL_XGMII_OOC_IMPL_DONE"
puts "MILESTONE=I5_FULL_DUAL_XGMII_OOC"
puts "PART=$part_name"
puts "CLOCK_PERIOD_NS=6.400"
puts "OUT_DIR=$out_dir"
quit
