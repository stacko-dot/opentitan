// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Description: entropy_src core module
//

module entropy_src_core import entropy_src_pkg::*; #(
  parameter int EsFifoDepth = 4
) (
  input logic clk_i,
  input logic rst_ni,

  input  entropy_src_reg_pkg::entropy_src_reg2hw_t reg2hw,
  output entropy_src_reg_pkg::entropy_src_hw2reg_t hw2reg,

  // Efuse Interface
  input logic efuse_es_sw_reg_en_i,
  input logic efuse_es_sw_ov_en_i,

  // RNG Interface
  output logic rng_fips_o,


  // Entropy Interface
  input  entropy_src_hw_if_req_t entropy_src_hw_if_i,
  output entropy_src_hw_if_rsp_t entropy_src_hw_if_o,

  // RNG Interface
  output entropy_src_rng_req_t entropy_src_rng_o,
  input  entropy_src_rng_rsp_t entropy_src_rng_i,

  // CSRNG Interface
  output cs_aes_halt_req_t cs_aes_halt_o,
  input  cs_aes_halt_rsp_t cs_aes_halt_i,

  // External Health Test Interface
  output entropy_src_xht_req_t entropy_src_xht_o,
  input  entropy_src_xht_rsp_t entropy_src_xht_i,

  output logic           recov_alert_test_o,
  output logic           fatal_alert_test_o,
  output logic           recov_alert_o,
  output logic           fatal_alert_o,

  output logic           intr_es_entropy_valid_o,
  output logic           intr_es_health_test_failed_o,
  output logic           intr_es_observe_fifo_ready_o,
  output logic           intr_es_fatal_err_o
);

  import entropy_src_reg_pkg::*;

  localparam int Clog2EsFifoDepth = $clog2(EsFifoDepth);
  localparam int PostHTWidth = 32;
  localparam int RngBusWidth = 4;
  localparam int HalfRegWidth = 16;
  localparam int FullRegWidth = 32;
  localparam int EighthRegWidth = 4;
  localparam int SeedLen = 384;
  localparam int ObserveFifoWidth = 32;
  localparam int ObserveFifoDepth = 64;
  localparam int PreCondWidth = 64;
  localparam int Clog2ObserveFifoDepth = $clog2(ObserveFifoDepth);

  //-----------------------
  // SHA3 parameters
  //-----------------------
  // Do not enable masking
  localparam bit Sha3EnMasking = 0;
  // Needs EnMasking active to take effect
  localparam bit Sha3ReuseShare = 0;
  // derived parameter
  localparam int Sha3Share = (Sha3EnMasking) ? 2 : 1;

  // signals
  logic [RngBusWidth-1:0] lfsr_value;
  logic [RngBusWidth-1:0] seed_value;
  logic       load_seed;
  logic       fw_ov_mode;
  logic       fw_ov_entropy_insert;
  logic [ObserveFifoWidth-1:0] fw_ov_wr_data;
  logic       fw_ov_fifo_rd_pulse;
  logic       fw_ov_fifo_wr_pulse;
  logic       es_enable;
  logic       es_enable_early;
  logic       es_enable_lfsr;
  logic       es_enable_rng;
  logic       rng_bit_en;
  logic [1:0] rng_bit_sel;
  logic       lfsr_incr;
  logic       sw_es_rd_pulse;
  logic       event_es_entropy_valid;
  logic       event_es_health_test_failed;
  logic       event_es_observe_fifo_ready;
  logic       event_es_fatal_err;
  logic [15:0] es_rate;
  logic        es_rate_entropy_pulse;
  logic        es_rng_src_valid;
  logic [RngBusWidth-1:0] es_rng_bus;

  logic [RngBusWidth-1:0] sfifo_esrng_wdata;
  logic [RngBusWidth-1:0] sfifo_esrng_rdata;
  logic                   sfifo_esrng_push;
  logic                   sfifo_esrng_pop;
  logic                   sfifo_esrng_clr;
  logic                   sfifo_esrng_full;
  logic                   sfifo_esrng_not_empty;
  logic [2:0]             sfifo_esrng_err;

  logic [ObserveFifoWidth-1:0] sfifo_observe_wdata;
  logic [ObserveFifoWidth-1:0] sfifo_observe_rdata;
  logic                    sfifo_observe_push;
  logic                    sfifo_observe_pop;
  logic                    sfifo_observe_full;
  logic                    sfifo_observe_clr;
  logic                    sfifo_observe_not_empty;
  logic [Clog2ObserveFifoDepth:0] sfifo_observe_depth;
  logic [2:0]                     sfifo_observe_err;

  logic [Clog2EsFifoDepth:0] sfifo_esfinal_depth;
  logic [(1+SeedLen)-1:0] sfifo_esfinal_wdata;
  logic [(1+SeedLen)-1:0] sfifo_esfinal_rdata;
  logic                   sfifo_esfinal_push;
  logic                   sfifo_esfinal_pop;
  logic                   sfifo_esfinal_clr;
  logic                   sfifo_esfinal_not_full;
  logic                   sfifo_esfinal_full;
  logic                   sfifo_esfinal_not_empty;
  logic [2:0]             sfifo_esfinal_err;
  logic [SeedLen-1:0]     esfinal_data;
  logic                   esfinal_fips_flag;

  logic                   any_active;
  logic                   any_fail_pulse;
  logic                   main_stage_pop;
  logic                   bypass_stage_pop;
  logic [HalfRegWidth-1:0] any_fail_count;
  logic                    alert_threshold_fail;
  logic [HalfRegWidth-1:0] alert_threshold;
  logic [HalfRegWidth-1:0] alert_threshold_inv;
  logic                     recov_alert_event;
  logic [Clog2ObserveFifoDepth:0] observe_fifo_thresh;
  logic                     observe_fifo_thresh_met;
  logic                     repcnt_active;
  logic                     repcnts_active;
  logic                     adaptp_active;
  logic                     bucket_active;
  logic                     markov_active;
  logic                     extht_active;
  logic                     alert_cntrs_clr;
  logic                     health_test_clr;
  logic                     health_test_done_pulse;
  logic [RngBusWidth-1:0]   health_test_esbus;
  logic                     health_test_esbus_vld;
  logic                     es_route_to_sw;
  logic                     es_bypass_to_sw;
  logic                     es_bypass_mode;
  logic                     rst_bypass_mode;
  logic                     rst_alert_cntr;
  logic                     boot_bypass_disable;
  logic                     fips_compliance;

  logic [HalfRegWidth-1:0] health_test_fips_window;
  logic [HalfRegWidth-1:0] health_test_bypass_window;
  logic [HalfRegWidth-1:0] health_test_window;

  logic [HalfRegWidth-1:0] repcnt_fips_threshold;
  logic [HalfRegWidth-1:0] repcnt_fips_threshold_oneway;
  logic                    repcnt_fips_threshold_wr;
  logic [HalfRegWidth-1:0] repcnt_bypass_threshold;
  logic [HalfRegWidth-1:0] repcnt_bypass_threshold_oneway;
  logic                    repcnt_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] repcnt_threshold;
  logic [HalfRegWidth-1:0] repcnt_event_cnt;
  logic [HalfRegWidth-1:0] repcnt_event_hwm_fips;
  logic [HalfRegWidth-1:0] repcnt_event_hwm_bypass;
  logic [FullRegWidth-1:0] repcnt_total_fails;
  logic [EighthRegWidth-1:0] repcnt_fail_count;
  logic                     repcnt_fail_pulse;

  logic [HalfRegWidth-1:0] repcnts_fips_threshold;
  logic [HalfRegWidth-1:0] repcnts_fips_threshold_oneway;
  logic                    repcnts_fips_threshold_wr;
  logic [HalfRegWidth-1:0] repcnts_bypass_threshold;
  logic [HalfRegWidth-1:0] repcnts_bypass_threshold_oneway;
  logic                    repcnts_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] repcnts_threshold;
  logic [HalfRegWidth-1:0] repcnts_event_cnt;
  logic [HalfRegWidth-1:0] repcnts_event_hwm_fips;
  logic [HalfRegWidth-1:0] repcnts_event_hwm_bypass;
  logic [FullRegWidth-1:0] repcnts_total_fails;
  logic [EighthRegWidth-1:0] repcnts_fail_count;
  logic                     repcnts_fail_pulse;

  logic [HalfRegWidth-1:0] adaptp_hi_fips_threshold;
  logic [HalfRegWidth-1:0] adaptp_hi_fips_threshold_oneway;
  logic                    adaptp_hi_fips_threshold_wr;
  logic [HalfRegWidth-1:0] adaptp_hi_bypass_threshold;
  logic [HalfRegWidth-1:0] adaptp_hi_bypass_threshold_oneway;
  logic                    adaptp_hi_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] adaptp_hi_threshold;
  logic [HalfRegWidth-1:0] adaptp_lo_fips_threshold;
  logic [HalfRegWidth-1:0] adaptp_lo_fips_threshold_oneway;
  logic                    adaptp_lo_fips_threshold_wr;
  logic [HalfRegWidth-1:0] adaptp_lo_bypass_threshold;
  logic [HalfRegWidth-1:0] adaptp_lo_bypass_threshold_oneway;
  logic                    adaptp_lo_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] adaptp_lo_threshold;
  logic [HalfRegWidth-1:0] adaptp_event_cnt;
  logic [HalfRegWidth-1:0] adaptp_hi_event_hwm_fips;
  logic [HalfRegWidth-1:0] adaptp_hi_event_hwm_bypass;
  logic [HalfRegWidth-1:0] adaptp_lo_event_hwm_fips;
  logic [HalfRegWidth-1:0] adaptp_lo_event_hwm_bypass;
  logic [FullRegWidth-1:0] adaptp_hi_total_fails;
  logic [FullRegWidth-1:0] adaptp_lo_total_fails;
  logic [EighthRegWidth-1:0] adaptp_hi_fail_count;
  logic [EighthRegWidth-1:0] adaptp_lo_fail_count;
  logic                     adaptp_hi_fail_pulse;
  logic                     adaptp_lo_fail_pulse;

  logic [HalfRegWidth-1:0] bucket_fips_threshold;
  logic [HalfRegWidth-1:0] bucket_fips_threshold_oneway;
  logic                    bucket_fips_threshold_wr;
  logic [HalfRegWidth-1:0] bucket_bypass_threshold;
  logic [HalfRegWidth-1:0] bucket_bypass_threshold_oneway;
  logic                    bucket_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] bucket_threshold;
  logic [HalfRegWidth-1:0] bucket_event_cnt;
  logic [HalfRegWidth-1:0] bucket_event_hwm_fips;
  logic [HalfRegWidth-1:0] bucket_event_hwm_bypass;
  logic [FullRegWidth-1:0] bucket_total_fails;
  logic [EighthRegWidth-1:0] bucket_fail_count;
  logic                     bucket_fail_pulse;

  logic [HalfRegWidth-1:0] markov_hi_fips_threshold;
  logic [HalfRegWidth-1:0] markov_hi_fips_threshold_oneway;
  logic                    markov_hi_fips_threshold_wr;
  logic [HalfRegWidth-1:0] markov_hi_bypass_threshold;
  logic [HalfRegWidth-1:0] markov_hi_bypass_threshold_oneway;
  logic                    markov_hi_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] markov_hi_threshold;
  logic [HalfRegWidth-1:0] markov_lo_fips_threshold;
  logic [HalfRegWidth-1:0] markov_lo_fips_threshold_oneway;
  logic                    markov_lo_fips_threshold_wr;
  logic [HalfRegWidth-1:0] markov_lo_bypass_threshold;
  logic [HalfRegWidth-1:0] markov_lo_bypass_threshold_oneway;
  logic                    markov_lo_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] markov_lo_threshold;
  logic [HalfRegWidth-1:0] markov_hi_event_cnt;
  logic [HalfRegWidth-1:0] markov_lo_event_cnt;
  logic [HalfRegWidth-1:0] markov_hi_event_hwm_fips;
  logic [HalfRegWidth-1:0] markov_hi_event_hwm_bypass;
  logic [HalfRegWidth-1:0] markov_lo_event_hwm_fips;
  logic [HalfRegWidth-1:0] markov_lo_event_hwm_bypass;
  logic [FullRegWidth-1:0] markov_hi_total_fails;
  logic [FullRegWidth-1:0] markov_lo_total_fails;
  logic [EighthRegWidth-1:0] markov_hi_fail_count;
  logic [EighthRegWidth-1:0] markov_lo_fail_count;
  logic                     markov_hi_fail_pulse;
  logic                     markov_lo_fail_pulse;

  logic [HalfRegWidth-1:0] extht_hi_fips_threshold;
  logic [HalfRegWidth-1:0] extht_hi_fips_threshold_oneway;
  logic                    extht_hi_fips_threshold_wr;
  logic [HalfRegWidth-1:0] extht_hi_bypass_threshold;
  logic [HalfRegWidth-1:0] extht_hi_bypass_threshold_oneway;
  logic                    extht_hi_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] extht_hi_threshold;
  logic [HalfRegWidth-1:0] extht_lo_fips_threshold;
  logic [HalfRegWidth-1:0] extht_lo_fips_threshold_oneway;
  logic                    extht_lo_fips_threshold_wr;
  logic [HalfRegWidth-1:0] extht_lo_bypass_threshold;
  logic [HalfRegWidth-1:0] extht_lo_bypass_threshold_oneway;
  logic                    extht_lo_bypass_threshold_wr;
  logic [HalfRegWidth-1:0] extht_lo_threshold;
  logic [HalfRegWidth-1:0] extht_event_cnt;
  logic [HalfRegWidth-1:0] extht_hi_event_hwm_fips;
  logic [HalfRegWidth-1:0] extht_hi_event_hwm_bypass;
  logic [HalfRegWidth-1:0] extht_lo_event_hwm_fips;
  logic [HalfRegWidth-1:0] extht_lo_event_hwm_bypass;
  logic [FullRegWidth-1:0] extht_hi_total_fails;
  logic [FullRegWidth-1:0] extht_lo_total_fails;
  logic [EighthRegWidth-1:0] extht_hi_fail_count;
  logic [EighthRegWidth-1:0] extht_lo_fail_count;
  logic                     extht_hi_fail_pulse;
  logic                     extht_lo_fail_pulse;


  logic                     pfifo_esbit_wdata;
  logic [RngBusWidth-1:0]   pfifo_esbit_rdata;
  logic                     pfifo_esbit_not_empty;
  logic                     pfifo_esbit_push;
  logic                     pfifo_esbit_clr;
  logic                     pfifo_esbit_pop;

  logic [RngBusWidth-1:0]   pfifo_postht_wdata;
  logic [PostHTWidth-1:0]   pfifo_postht_rdata;
  logic                     pfifo_postht_not_empty;
  logic                     pfifo_postht_push;
  logic                     pfifo_postht_clr;
  logic                     pfifo_postht_pop;

  logic [PreCondWidth-1:0]  pfifo_cond_wdata;
  logic [SeedLen-1:0]       pfifo_cond_rdata;
  logic                     pfifo_cond_not_empty;
  logic                     pfifo_cond_push;

  logic [ObserveFifoWidth-1:0] pfifo_precon_wdata;
  logic [PreCondWidth-1:0]     pfifo_precon_rdata;
  logic                        pfifo_precon_not_empty;
  logic                        pfifo_precon_push;
  logic                        pfifo_precon_clr;
  logic                        pfifo_precon_pop;

  logic [PreCondWidth-1:0]  pfifo_bypass_wdata;
  logic [SeedLen-1:0]       pfifo_bypass_rdata;
  logic                     pfifo_bypass_not_empty;
  logic                     pfifo_bypass_push;
  logic                     pfifo_bypass_clr;
  logic                     pfifo_bypass_pop;

  logic [SeedLen-1:0]       pfifo_swread_wdata;
  logic                     pfifo_swread_not_full;
  logic [FullRegWidth-1:0]  pfifo_swread_rdata;
  logic                     pfifo_swread_not_empty;
  logic                     pfifo_swread_push;
  logic                     pfifo_swread_clr;
  logic                     pfifo_swread_pop;

  logic [SeedLen-1:0]       final_es_data;
  logic                     es_hw_if_req;
  logic                     es_hw_if_ack;
  logic                     es_hw_if_fifo_pop;
  logic                     sfifo_esrng_err_sum;
  logic                     sfifo_observe_err_sum;
  logic                     sfifo_esfinal_err_sum;
  logic                     es_ack_sm_err_sum;
  logic                     es_ack_sm_err;
  logic                     es_main_sm_err_sum;
  logic                     es_main_sm_err;
  logic                     es_main_sm_alert;
  logic                     es_main_sm_idle;
  logic [7:0]               es_main_sm_state;
  logic                     fifo_write_err_sum;
  logic                     fifo_read_err_sum;
  logic                     fifo_status_err_sum;
  logic [30:0]              err_code_test_bit;
  logic                     sha3_msgfifo_ready;
  logic                     sha3_state_vld;
  logic                     sha3_start;
  logic                     sha3_process;
  logic                     sha3_block_processed;
  logic                     sha3_done;
  logic                     sha3_absorbed;
  logic                     sha3_squeezing;
  logic [2:0]               sha3_fsm;
  logic [32:0]              sha3_err;
  logic                     cs_aes_halt_req;
  logic                     sha3_msg_rdy;


  logic [sha3_pkg::StateW-1:0] sha3_state[Sha3Share];
  logic [PreCondWidth-1:0] msg_data[Sha3Share];

  logic                    unused_err_code_test_bit;
  logic                    unused_sha3_state;
  logic                    unused_entropy_data;
  logic                    unused_fw_ov_rd_data;

  // flops
  logic [15:0] es_rate_cntr_q, es_rate_cntr_d;
  logic        lfsr_incr_dly_q, lfsr_incr_dly_d;
  logic [RngBusWidth-1:0] ht_esbus_dly_q, ht_esbus_dly_d;
  logic        ht_esbus_vld_dly_q, ht_esbus_vld_dly_d;
  logic        ht_esbus_vld_dly2_q, ht_esbus_vld_dly2_d;
  logic        boot_bypass_q, boot_bypass_d;
  logic        ht_failed_q, ht_failed_d;
  logic        ht_failed_pulse_q, ht_failed_pulse_d;
  logic        ht_done_pulse_q, ht_done_pulse_d;
  logic [HalfRegWidth-1:0] window_cntr_q, window_cntr_d;
  logic                    sha3_msg_rdy_q, sha3_msg_rdy_d;
  logic                    sha3_err_q, sha3_err_d;
  logic        cs_aes_halt_q, cs_aes_halt_d;
  logic [1:0]  es_enable_q, es_enable_d;

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      es_rate_cntr_q        <= 16'h0001;
      lfsr_incr_dly_q       <= '0;
      boot_bypass_q         <= 1'b1;
      ht_failed_q           <= '0;
      ht_failed_pulse_q     <= '0;
      ht_done_pulse_q       <= '0;
      ht_esbus_dly_q        <= '0;
      ht_esbus_vld_dly_q    <= '0;
      ht_esbus_vld_dly2_q   <= '0;
      window_cntr_q         <= '0;
      sha3_msg_rdy_q        <= '0;
      sha3_err_q            <= '0;
      cs_aes_halt_q         <= '0;
      es_enable_q           <= '0;
    end else begin
      es_rate_cntr_q        <= es_rate_cntr_d;
      lfsr_incr_dly_q       <= lfsr_incr_dly_d;
      boot_bypass_q         <= boot_bypass_d;
      ht_failed_q           <= ht_failed_d;
      ht_failed_pulse_q     <= ht_failed_pulse_d;
      ht_done_pulse_q       <= ht_done_pulse_d;
      ht_esbus_dly_q        <= ht_esbus_dly_d;
      ht_esbus_vld_dly_q    <= ht_esbus_vld_dly_d;
      ht_esbus_vld_dly2_q   <= ht_esbus_vld_dly2_d;
      window_cntr_q         <= window_cntr_d;
      sha3_msg_rdy_q        <= sha3_msg_rdy_d;
      sha3_err_q            <= sha3_err_d;
      cs_aes_halt_q         <= cs_aes_halt_d;
      es_enable_q           <= es_enable_d;
    end

  assign es_enable_d = reg2hw.conf.enable.q;
  assign es_enable_early = (|reg2hw.conf.enable.q);
  assign es_enable = (|es_enable_q);
  assign es_enable_lfsr = es_enable_q[1];
  assign es_enable_rng = es_enable_q[0];
  assign load_seed = !es_enable;
  assign hw2reg.regwen.d = !es_enable; // hw reg lock implementation
  assign observe_fifo_thresh = reg2hw.observe_fifo_thresh.q;

  // firmware override controls
  assign fw_ov_mode = efuse_es_sw_ov_en_i && reg2hw.fw_ov_control.fw_ov_mode.q;
  assign fw_ov_entropy_insert = reg2hw.fw_ov_control.fw_ov_entropy_insert.q;
  assign fw_ov_fifo_rd_pulse = reg2hw.fw_ov_rd_data.re;
  assign hw2reg.fw_ov_rd_data.d = sfifo_observe_rdata;
  assign fw_ov_fifo_wr_pulse = reg2hw.fw_ov_wr_data.qe;
  assign fw_ov_wr_data = reg2hw.fw_ov_wr_data.q;

  assign entropy_src_rng_o.rng_enable = es_enable_rng;

  assign es_rng_src_valid = entropy_src_rng_i.rng_valid;
  assign es_rng_bus = entropy_src_rng_i.rng_b;


  //--------------------------------------------
  // instantiate interrupt hardware primitives
  //--------------------------------------------

  prim_intr_hw #(
    .Width(1)
  ) u_intr_hw_es_entropy_valid (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .event_intr_i           (event_es_entropy_valid),
    .reg2hw_intr_enable_q_i (reg2hw.intr_enable.es_entropy_valid.q),
    .reg2hw_intr_test_q_i   (reg2hw.intr_test.es_entropy_valid.q),
    .reg2hw_intr_test_qe_i  (reg2hw.intr_test.es_entropy_valid.qe),
    .reg2hw_intr_state_q_i  (reg2hw.intr_state.es_entropy_valid.q),
    .hw2reg_intr_state_de_o (hw2reg.intr_state.es_entropy_valid.de),
    .hw2reg_intr_state_d_o  (hw2reg.intr_state.es_entropy_valid.d),
    .intr_o                 (intr_es_entropy_valid_o)
  );

  prim_intr_hw #(
    .Width(1)
  ) u_intr_hw_es_health_test_failed (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .event_intr_i           (event_es_health_test_failed),
    .reg2hw_intr_enable_q_i (reg2hw.intr_enable.es_health_test_failed.q),
    .reg2hw_intr_test_q_i   (reg2hw.intr_test.es_health_test_failed.q),
    .reg2hw_intr_test_qe_i  (reg2hw.intr_test.es_health_test_failed.qe),
    .reg2hw_intr_state_q_i  (reg2hw.intr_state.es_health_test_failed.q),
    .hw2reg_intr_state_de_o (hw2reg.intr_state.es_health_test_failed.de),
    .hw2reg_intr_state_d_o  (hw2reg.intr_state.es_health_test_failed.d),
    .intr_o                 (intr_es_health_test_failed_o)
  );

  prim_intr_hw #(
    .Width(1)
  ) u_intr_hw_es_observe_fifo_ready (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .event_intr_i           (event_es_observe_fifo_ready),
    .reg2hw_intr_enable_q_i (reg2hw.intr_enable.es_observe_fifo_ready.q),
    .reg2hw_intr_test_q_i   (reg2hw.intr_test.es_observe_fifo_ready.q),
    .reg2hw_intr_test_qe_i  (reg2hw.intr_test.es_observe_fifo_ready.qe),
    .reg2hw_intr_state_q_i  (reg2hw.intr_state.es_observe_fifo_ready.q),
    .hw2reg_intr_state_de_o (hw2reg.intr_state.es_observe_fifo_ready.de),
    .hw2reg_intr_state_d_o  (hw2reg.intr_state.es_observe_fifo_ready.d),
    .intr_o                 (intr_es_observe_fifo_ready_o)
  );

  prim_intr_hw #(
    .Width(1)
  ) u_intr_hw_es_fatal_err (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .event_intr_i           (event_es_fatal_err),
    .reg2hw_intr_enable_q_i (reg2hw.intr_enable.es_fatal_err.q),
    .reg2hw_intr_test_q_i   (reg2hw.intr_test.es_fatal_err.q),
    .reg2hw_intr_test_qe_i  (reg2hw.intr_test.es_fatal_err.qe),
    .reg2hw_intr_state_q_i  (reg2hw.intr_state.es_fatal_err.q),
    .hw2reg_intr_state_de_o (hw2reg.intr_state.es_fatal_err.de),
    .hw2reg_intr_state_d_o  (hw2reg.intr_state.es_fatal_err.d),
    .intr_o                 (intr_es_fatal_err_o)
  );

  //--------------------------------------------
  // lfsr - a version of a entropy source
  //--------------------------------------------

  assign lfsr_incr = es_enable_lfsr && es_rate_entropy_pulse;
  assign lfsr_incr_dly_d =
         !es_enable ? 1'b0 :
         lfsr_incr;

  prim_lfsr #(
    .LfsrDw(RngBusWidth),
    .EntropyDw(RngBusWidth),
    .StateOutDw(RngBusWidth),
    .DefaultSeed(1),
    .CustomCoeffs('0)
  ) u_prim_lfsr (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .seed_en_i      (load_seed),
    .seed_i         (seed_value),
    .lfsr_en_i      (lfsr_incr_dly_q),
    .entropy_i      ('0),
    .state_o        (lfsr_value)
  );

  // entropy rate limiter

  assign es_rate_cntr_d =
         !es_enable ? 16'h0001 :
         (es_rate == '0) ? 16'h0000 :
         es_rate_entropy_pulse ? es_rate :
         (es_rate_cntr_q - 1);

  assign es_rate_entropy_pulse =
         !es_enable ? 1'b0 :
         (es_rate == '0) ? 1'b0 :
         (es_rate_cntr_q == 16'h0001);

  //--------------------------------------------
  // tlul register settings
  //--------------------------------------------


  // seed register
  assign seed_value = reg2hw.seed.q;

  // es rate register
  assign es_rate = reg2hw.rate.q;

  // set the interrupt event when enabled
  assign event_es_entropy_valid = pfifo_swread_not_empty;


  // set the interrupt sources
  assign event_es_fatal_err = es_enable && (
         sfifo_esrng_err_sum ||
         sfifo_observe_err_sum ||
         sfifo_esfinal_err_sum ||
         es_ack_sm_err_sum ||
         es_main_sm_err_sum);

  // set fifo errors that are single instances of source
  assign sfifo_esrng_err_sum = (|sfifo_esrng_err) ||
         err_code_test_bit[0];
  assign sfifo_observe_err_sum = (|sfifo_observe_err) ||
         err_code_test_bit[1];
  assign sfifo_esfinal_err_sum = (|sfifo_esfinal_err) ||
         err_code_test_bit[2];
  assign es_ack_sm_err_sum = es_ack_sm_err ||
         err_code_test_bit[20];
  assign es_main_sm_err_sum = es_main_sm_err ||
         err_code_test_bit[21];
  assign fifo_write_err_sum =
         sfifo_esrng_err[2] ||
         sfifo_observe_err[2] ||
         sfifo_esfinal_err[2] ||
         err_code_test_bit[28];
  assign fifo_read_err_sum =
         sfifo_esrng_err[1] ||
         sfifo_observe_err[1] ||
         sfifo_esfinal_err[1] ||
         err_code_test_bit[29];
  assign fifo_status_err_sum =
         sfifo_esrng_err[0] ||
         sfifo_observe_err[0] ||
         sfifo_esfinal_err[0] ||
         err_code_test_bit[30];

  // set the err code source bits
  assign hw2reg.err_code.sfifo_esrng_err.d = 1'b1;
  assign hw2reg.err_code.sfifo_esrng_err.de =  es_enable && sfifo_esrng_err_sum;

  assign hw2reg.err_code.sfifo_observe_err.d = 1'b1;
  assign hw2reg.err_code.sfifo_observe_err.de =  es_enable && sfifo_observe_err_sum;

  assign hw2reg.err_code.sfifo_esfinal_err.d = 1'b1;
  assign hw2reg.err_code.sfifo_esfinal_err.de =  es_enable && sfifo_esfinal_err_sum;

  assign hw2reg.err_code.es_ack_sm_err.d = 1'b1;
  assign hw2reg.err_code.es_ack_sm_err.de = es_enable && es_ack_sm_err_sum;

  assign hw2reg.err_code.es_main_sm_err.d = 1'b1;
  assign hw2reg.err_code.es_main_sm_err.de = es_enable && es_main_sm_err_sum;


 // set the err code type bits
  assign hw2reg.err_code.fifo_write_err.d = 1'b1;
  assign hw2reg.err_code.fifo_write_err.de = es_enable && fifo_write_err_sum;

  assign hw2reg.err_code.fifo_read_err.d = 1'b1;
  assign hw2reg.err_code.fifo_read_err.de = es_enable && fifo_read_err_sum;

  assign hw2reg.err_code.fifo_state_err.d = 1'b1;
  assign hw2reg.err_code.fifo_state_err.de = es_enable && fifo_status_err_sum;

  // Error forcing
  for (genvar i = 0; i < 31; i = i+1) begin : gen_err_code_test_bit
    assign err_code_test_bit[i] = (reg2hw.err_code_test.q == i) && reg2hw.err_code_test.qe;
  end : gen_err_code_test_bit

  // alert - send all interrupt sources to the alert for the fatal case
  assign fatal_alert_o = event_es_fatal_err;

  // alert test
  assign recov_alert_test_o = {
    reg2hw.alert_test.recov_alert.q &&
    reg2hw.alert_test.recov_alert.qe
  };
  assign fatal_alert_test_o = {
    reg2hw.alert_test.fatal_alert.q &&
    reg2hw.alert_test.fatal_alert.qe
  };


  // set the debug status reg
  assign hw2reg.debug_status.entropy_fifo_depth.d = sfifo_esfinal_depth;
  assign hw2reg.debug_status.sha3_fsm.d = sha3_fsm;
  assign hw2reg.debug_status.sha3_block_pr.d = sha3_block_processed;
  assign hw2reg.debug_status.sha3_squeezing.d = sha3_squeezing;
  assign hw2reg.debug_status.sha3_absorbed.d = sha3_absorbed;
  assign hw2reg.debug_status.sha3_err.d = sha3_err_q;

  assign sha3_err_d =
         es_enable ? 1'b0 :
         {|sha3_err} ? 1'b1 :
         sha3_err_q;

  // state machine status
  assign hw2reg.debug_status.main_sm_idle.d = es_main_sm_idle;
  assign hw2reg.debug_status.main_sm_state.d = es_main_sm_state;

  //--------------------------------------------
  // receive in RNG bus input
  //--------------------------------------------


  prim_fifo_sync #(
    .Width(RngBusWidth),
    .Pass(0),
    .Depth(2)
  ) u_prim_fifo_sync_esrng (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (sfifo_esrng_clr),
    .wvalid_i   (sfifo_esrng_push),
    .wdata_i    (sfifo_esrng_wdata),
    .wready_o   (),
    .rvalid_o   (sfifo_esrng_not_empty),
    .rdata_o    (sfifo_esrng_rdata),
    .rready_i   (sfifo_esrng_pop),
    .full_o     (sfifo_esrng_full),
    .depth_o    ()
  );

  // fifo controls
  assign sfifo_esrng_push = (es_enable_rng && es_rng_src_valid);

  assign sfifo_esrng_clr  = !es_enable;
  assign sfifo_esrng_wdata = es_rng_bus;
  assign sfifo_esrng_pop = es_enable_rng && sfifo_esrng_not_empty;

  // fifo err
  assign sfifo_esrng_err =
         {1'b0,
         (sfifo_esrng_pop && !sfifo_esrng_not_empty),
         (sfifo_esrng_full && !sfifo_esrng_not_empty)};


  // pack esrng bus into signal bit packer

  assign rng_bit_en = reg2hw.conf.rng_bit_en.q;
  assign rng_bit_sel = reg2hw.conf.rng_bit_sel.q;

  prim_packer_fifo #(
    .InW(1),
    .OutW(RngBusWidth)
  ) u_prim_packer_fifo_esbit (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (pfifo_esbit_clr),
    .wvalid_i   (pfifo_esbit_push),
    .wdata_i    (pfifo_esbit_wdata),
    .wready_o   (),
    .rvalid_o   (pfifo_esbit_not_empty),
    .rdata_o    (pfifo_esbit_rdata),
    .rready_i   (pfifo_esbit_pop),
    .depth_o    ()
  );

  assign pfifo_esbit_push = rng_bit_en && sfifo_esrng_pop && es_rate_entropy_pulse;
  assign pfifo_esbit_clr = !es_enable;
  assign pfifo_esbit_pop = es_rate_entropy_pulse && pfifo_esbit_not_empty;
  assign pfifo_esbit_wdata =
         (rng_bit_sel == 2'h0) ? sfifo_esrng_rdata[0] :
         (rng_bit_sel == 2'h1) ? sfifo_esrng_rdata[1] :
         (rng_bit_sel == 2'h2) ? sfifo_esrng_rdata[2] :
         sfifo_esrng_rdata[3];


  // select source for health testing

  assign health_test_esbus = es_enable_lfsr ? lfsr_value :
         (es_enable_rng && rng_bit_en) ? pfifo_esbit_rdata :
         sfifo_esrng_rdata;

  assign health_test_esbus_vld = es_enable_lfsr ? es_rate_entropy_pulse :
         (es_enable_rng && rng_bit_en) ? pfifo_esbit_pop :
         sfifo_esrng_pop;

  assign ht_esbus_vld_dly_d = es_enable && health_test_esbus_vld;
  assign ht_esbus_dly_d     = es_enable ? health_test_esbus : '0;
  assign ht_esbus_vld_dly2_d = es_enable && ht_esbus_vld_dly_q;

  assign repcnt_active = !reg2hw.conf.repcnt_disable.q && es_enable;
  assign repcnts_active = !reg2hw.conf.repcnts_disable.q && es_enable;
  assign adaptp_active = !reg2hw.conf.adaptp_disable.q && es_enable;
  assign bucket_active = !reg2hw.conf.bucket_disable.q && es_enable;
  assign markov_active = !reg2hw.conf.markov_disable.q && es_enable;
  assign extht_active = reg2hw.conf.extht_enable.q && es_enable;

  assign health_test_clr = reg2hw.conf.health_test_clr.q;

  assign health_test_fips_window = reg2hw.health_test_windows.fips_window.q;
  assign health_test_bypass_window = reg2hw.health_test_windows.bypass_window.q;

  assign repcnt_fips_threshold = reg2hw.repcnt_thresholds.fips_thresh.q;
  assign repcnt_fips_threshold_wr = reg2hw.repcnt_thresholds.fips_thresh.qe;
  assign hw2reg.repcnt_thresholds.fips_thresh.d = repcnt_fips_threshold_oneway;
  assign repcnt_bypass_threshold = reg2hw.repcnt_thresholds.bypass_thresh.q;
  assign repcnt_bypass_threshold_wr = reg2hw.repcnt_thresholds.bypass_thresh.qe;
  assign hw2reg.repcnt_thresholds.bypass_thresh.d = repcnt_bypass_threshold_oneway;

  assign repcnts_fips_threshold = reg2hw.repcnts_thresholds.fips_thresh.q;
  assign repcnts_fips_threshold_wr = reg2hw.repcnts_thresholds.fips_thresh.qe;
  assign hw2reg.repcnts_thresholds.fips_thresh.d = repcnts_fips_threshold_oneway;
  assign repcnts_bypass_threshold = reg2hw.repcnts_thresholds.bypass_thresh.q;
  assign repcnts_bypass_threshold_wr = reg2hw.repcnts_thresholds.bypass_thresh.qe;
  assign hw2reg.repcnts_thresholds.bypass_thresh.d = repcnts_bypass_threshold_oneway;


  assign adaptp_hi_fips_threshold = reg2hw.adaptp_hi_thresholds.fips_thresh.q;
  assign adaptp_hi_fips_threshold_wr = reg2hw.adaptp_hi_thresholds.fips_thresh.qe;
  assign hw2reg.adaptp_hi_thresholds.fips_thresh.d = adaptp_hi_fips_threshold_oneway;
  assign adaptp_hi_bypass_threshold = reg2hw.adaptp_hi_thresholds.bypass_thresh.q;
  assign adaptp_hi_bypass_threshold_wr = reg2hw.adaptp_hi_thresholds.bypass_thresh.qe;
  assign hw2reg.adaptp_hi_thresholds.bypass_thresh.d = adaptp_hi_bypass_threshold_oneway;

  assign adaptp_lo_fips_threshold = reg2hw.adaptp_lo_thresholds.fips_thresh.q;
  assign adaptp_lo_fips_threshold_wr = reg2hw.adaptp_lo_thresholds.fips_thresh.qe;
  assign hw2reg.adaptp_lo_thresholds.fips_thresh.d = adaptp_lo_fips_threshold_oneway;
  assign adaptp_lo_bypass_threshold = reg2hw.adaptp_lo_thresholds.bypass_thresh.q;
  assign adaptp_lo_bypass_threshold_wr = reg2hw.adaptp_lo_thresholds.bypass_thresh.qe;
  assign hw2reg.adaptp_lo_thresholds.bypass_thresh.d = adaptp_lo_bypass_threshold_oneway;


  assign bucket_fips_threshold = reg2hw.bucket_thresholds.fips_thresh.q;
  assign bucket_fips_threshold_wr = reg2hw.bucket_thresholds.fips_thresh.qe;
  assign hw2reg.bucket_thresholds.fips_thresh.d = bucket_fips_threshold_oneway;
  assign bucket_bypass_threshold = reg2hw.bucket_thresholds.bypass_thresh.q;
  assign bucket_bypass_threshold_wr = reg2hw.bucket_thresholds.bypass_thresh.qe;
  assign hw2reg.bucket_thresholds.bypass_thresh.d = bucket_bypass_threshold_oneway;


  assign markov_hi_fips_threshold = reg2hw.markov_hi_thresholds.fips_thresh.q;
  assign markov_hi_fips_threshold_wr = reg2hw.markov_hi_thresholds.fips_thresh.qe;
  assign hw2reg.markov_hi_thresholds.fips_thresh.d = markov_hi_fips_threshold_oneway;
  assign markov_hi_bypass_threshold = reg2hw.markov_hi_thresholds.bypass_thresh.q;
  assign markov_hi_bypass_threshold_wr = reg2hw.markov_hi_thresholds.bypass_thresh.qe;
  assign hw2reg.markov_hi_thresholds.bypass_thresh.d = markov_hi_bypass_threshold_oneway;

  assign markov_lo_fips_threshold = reg2hw.markov_lo_thresholds.fips_thresh.q;
  assign markov_lo_fips_threshold_wr = reg2hw.markov_lo_thresholds.fips_thresh.qe;
  assign hw2reg.markov_lo_thresholds.fips_thresh.d = markov_lo_fips_threshold_oneway;
  assign markov_lo_bypass_threshold = reg2hw.markov_lo_thresholds.bypass_thresh.q;
  assign markov_lo_bypass_threshold_wr = reg2hw.markov_lo_thresholds.bypass_thresh.qe;
  assign hw2reg.markov_lo_thresholds.bypass_thresh.d = markov_lo_bypass_threshold_oneway;


  assign extht_hi_fips_threshold = reg2hw.extht_hi_thresholds.fips_thresh.q;
  assign extht_hi_fips_threshold_wr = reg2hw.extht_hi_thresholds.fips_thresh.qe;
  assign hw2reg.extht_hi_thresholds.fips_thresh.d = extht_hi_fips_threshold_oneway;
  assign extht_hi_bypass_threshold = reg2hw.extht_hi_thresholds.bypass_thresh.q;
  assign extht_hi_bypass_threshold_wr = reg2hw.extht_hi_thresholds.bypass_thresh.qe;
  assign hw2reg.extht_hi_thresholds.bypass_thresh.d = extht_hi_bypass_threshold_oneway;

  assign extht_lo_fips_threshold = reg2hw.extht_lo_thresholds.fips_thresh.q;
  assign extht_lo_fips_threshold_wr = reg2hw.extht_lo_thresholds.fips_thresh.qe;
  assign hw2reg.extht_lo_thresholds.fips_thresh.d = extht_lo_fips_threshold_oneway;
  assign extht_lo_bypass_threshold = reg2hw.extht_lo_thresholds.bypass_thresh.q;
  assign extht_lo_bypass_threshold_wr = reg2hw.extht_lo_thresholds.bypass_thresh.qe;
  assign hw2reg.extht_lo_thresholds.bypass_thresh.d = extht_lo_bypass_threshold_oneway;



  assign health_test_window = es_bypass_mode ? health_test_bypass_window : health_test_fips_window;

  //------------------------------
  // repcnt one-way thresholds
  //------------------------------
  assign repcnt_threshold = es_bypass_mode ? repcnt_bypass_threshold_oneway :
         repcnt_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_repcnt_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (repcnt_fips_threshold_wr),
    .value_i             (repcnt_fips_threshold),
    .value_o             (repcnt_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_repcnt_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (repcnt_bypass_threshold_wr),
    .value_i             (repcnt_bypass_threshold),
    .value_o             (repcnt_bypass_threshold_oneway)
  );

  //------------------------------
  // repcnts one-way thresholds
  //------------------------------
  assign repcnts_threshold = es_bypass_mode ? repcnts_bypass_threshold_oneway :
         repcnts_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_repcnts_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (repcnts_fips_threshold_wr),
    .value_i             (repcnts_fips_threshold),
    .value_o             (repcnts_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_repcnts_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (repcnts_bypass_threshold_wr),
    .value_i             (repcnts_bypass_threshold),
    .value_o             (repcnts_bypass_threshold_oneway)
  );


  //------------------------------
  // adaptp one-way thresholds
  //------------------------------
  assign adaptp_hi_threshold = es_bypass_mode ? adaptp_hi_bypass_threshold_oneway :
         adaptp_hi_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_adaptp_hi_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (adaptp_hi_fips_threshold_wr),
    .value_i             (adaptp_hi_fips_threshold),
    .value_o             (adaptp_hi_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_adaptp_hi_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (adaptp_hi_bypass_threshold_wr),
    .value_i             (adaptp_hi_bypass_threshold),
    .value_o             (adaptp_hi_bypass_threshold_oneway)
  );

  assign adaptp_lo_threshold = es_bypass_mode ? adaptp_lo_bypass_threshold_oneway :
         adaptp_lo_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_adaptp_lo_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (adaptp_lo_fips_threshold_wr),
    .value_i             (adaptp_lo_fips_threshold),
    .value_o             (adaptp_lo_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_adaptp_lo_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (adaptp_lo_bypass_threshold_wr),
    .value_i             (adaptp_lo_bypass_threshold),
    .value_o             (adaptp_lo_bypass_threshold_oneway)
  );


  //------------------------------
  // bucket one-way thresholds
  //------------------------------
  assign bucket_threshold = es_bypass_mode ? bucket_bypass_threshold_oneway :
         bucket_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_bucket_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (bucket_fips_threshold_wr),
    .value_i             (bucket_fips_threshold),
    .value_o             (bucket_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_bucket_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (bucket_bypass_threshold_wr),
    .value_i             (bucket_bypass_threshold),
    .value_o             (bucket_bypass_threshold_oneway)
  );


  //------------------------------
  // markov one-way thresholds
  //------------------------------
  assign markov_hi_threshold = es_bypass_mode ? markov_hi_bypass_threshold_oneway :
         markov_hi_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_markov_hi_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (markov_hi_fips_threshold_wr),
    .value_i             (markov_hi_fips_threshold),
    .value_o             (markov_hi_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_markov_hi_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (markov_hi_bypass_threshold_wr),
    .value_i             (markov_hi_bypass_threshold),
    .value_o             (markov_hi_bypass_threshold_oneway)
  );

  assign markov_lo_threshold = es_bypass_mode ? markov_lo_bypass_threshold_oneway :
         markov_lo_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_markov_lo_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (markov_lo_fips_threshold_wr),
    .value_i             (markov_lo_fips_threshold),
    .value_o             (markov_lo_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_markov_lo_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (markov_lo_bypass_threshold_wr),
    .value_i             (markov_lo_bypass_threshold),
    .value_o             (markov_lo_bypass_threshold_oneway)
  );


  //------------------------------
  // extht one-way thresholds
  //------------------------------
  assign extht_hi_threshold = es_bypass_mode ? extht_hi_bypass_threshold_oneway :
         extht_hi_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_extht_hi_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (extht_hi_fips_threshold_wr),
    .value_i             (extht_hi_fips_threshold),
    .value_o             (extht_hi_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_extht_hi_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (extht_hi_bypass_threshold_wr),
    .value_i             (extht_hi_bypass_threshold),
    .value_o             (extht_hi_bypass_threshold_oneway)
  );


  assign extht_lo_threshold = es_bypass_mode ? extht_lo_bypass_threshold_oneway :
         extht_lo_fips_threshold_oneway;

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_extht_lo_thresh_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (extht_lo_fips_threshold_wr),
    .value_i             (extht_lo_fips_threshold),
    .value_o             (extht_lo_fips_threshold_oneway)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_extht_lo_thresh_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (1'b0),
    .active_i            (1'b1),
    .event_i             (extht_lo_bypass_threshold_wr),
    .value_i             (extht_lo_bypass_threshold),
    .value_o             (extht_lo_bypass_threshold_oneway)
  );



  //------------------------------
  // misc control settings
  //------------------------------

  assign event_es_health_test_failed = recov_alert_event;
  assign event_es_observe_fifo_ready = observe_fifo_thresh_met;

  assign es_route_to_sw = reg2hw.entropy_control.es_route.q;
  assign es_bypass_to_sw = reg2hw.entropy_control.es_type.q;
  assign boot_bypass_disable = reg2hw.conf.boot_bypass_disable.q;

  assign boot_bypass_d =
         (!es_enable_early) ? 1'b1 :  // special case for reset
         boot_bypass_disable ? 1'b0 :
         rst_bypass_mode ? 1'b0 :
         boot_bypass_q;

  assign es_bypass_mode = boot_bypass_q || es_bypass_to_sw;

  // send off to AST RNG for possibly faster entropy generation
  assign rng_fips_o = es_bypass_mode;

  //--------------------------------------------
  // common health test window counter
  //--------------------------------------------

  // Window counter
  assign window_cntr_d =
         (!es_enable) ? '0 :
         health_test_clr ? '0 :
         health_test_done_pulse ? '0  :
         health_test_esbus_vld ? (window_cntr_q+1) :
         window_cntr_q;

  // Window wrap condition
  assign health_test_done_pulse = (window_cntr_q == health_test_window);

  //--------------------------------------------
  // repetitive count test
  //--------------------------------------------

  entropy_src_repcnt_ht #(
    .RegWidth(HalfRegWidth),
    .RngBusWidth(RngBusWidth)
  ) u_entropy_src_repcnt_ht (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .entropy_bit_i       (health_test_esbus),
    .entropy_bit_vld_i   (health_test_esbus_vld),
    .clear_i             (health_test_clr),
    .active_i            (repcnt_active),
    .thresh_i            (repcnt_threshold),
    .test_cnt_o          (repcnt_event_cnt),
    .test_fail_pulse_o   (repcnt_fail_pulse)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_repcnt_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnt_active),
    .event_i             (repcnt_fail_pulse && !es_bypass_mode),
    .value_i             (repcnt_event_cnt),
    .value_o             (repcnt_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_repcnt_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnt_active),
    .event_i             (repcnt_fail_pulse && es_bypass_mode),
    .value_i             (repcnt_event_cnt),
    .value_o             (repcnt_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_repcnt (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnt_active),
    .event_i             (repcnt_fail_pulse),
    .value_o             (repcnt_total_fails)
  );

  assign hw2reg.repcnt_hi_watermarks.fips_watermark.d = repcnt_event_hwm_fips;
  assign hw2reg.repcnt_hi_watermarks.bypass_watermark.d = repcnt_event_hwm_bypass;
  assign hw2reg.repcnt_total_fails.d = repcnt_total_fails;

  //--------------------------------------------
  // repetitive count symbol test
  //--------------------------------------------

  entropy_src_repcnts_ht #(
    .RegWidth(HalfRegWidth),
    .RngBusWidth(RngBusWidth)
  ) u_entropy_src_repcnts_ht (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .entropy_bit_i       (health_test_esbus),
    .entropy_bit_vld_i   (health_test_esbus_vld),
    .clear_i             (health_test_clr),
    .active_i            (repcnts_active),
    .thresh_i            (repcnts_threshold),
    .test_cnt_o          (repcnts_event_cnt),
    .test_fail_pulse_o   (repcnts_fail_pulse)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_repcnts_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnts_active),
    .event_i             (repcnts_fail_pulse && !es_bypass_mode),
    .value_i             (repcnts_event_cnt),
    .value_o             (repcnts_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_repcnts_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnts_active),
    .event_i             (repcnts_fail_pulse && es_bypass_mode),
    .value_i             (repcnts_event_cnt),
    .value_o             (repcnts_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_repcnts (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (repcnts_active),
    .event_i             (repcnts_fail_pulse),
    .value_o             (repcnts_total_fails)
  );

  assign hw2reg.repcnts_hi_watermarks.fips_watermark.d = repcnts_event_hwm_fips;
  assign hw2reg.repcnts_hi_watermarks.bypass_watermark.d = repcnts_event_hwm_bypass;
  assign hw2reg.repcnts_total_fails.d = repcnts_total_fails;

  //--------------------------------------------
  // adaptive proportion test
  //--------------------------------------------

  entropy_src_adaptp_ht #(
    .RegWidth(HalfRegWidth),
    .RngBusWidth(RngBusWidth)
  ) u_entropy_src_adaptp_ht (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .entropy_bit_i       (health_test_esbus),
    .entropy_bit_vld_i   (health_test_esbus_vld),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .thresh_hi_i         (adaptp_hi_threshold),
    .thresh_lo_i         (adaptp_lo_threshold),
    .window_wrap_pulse_i (health_test_done_pulse),
    .test_cnt_o          (adaptp_event_cnt),
    .test_fail_hi_pulse_o(adaptp_hi_fail_pulse),
    .test_fail_lo_pulse_o(adaptp_lo_fail_pulse)
  );


  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_adaptp_hi_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_hi_fail_pulse && !es_bypass_mode),
    .value_i             (adaptp_event_cnt),
    .value_o             (adaptp_hi_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_adaptp_hi_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_hi_fail_pulse && es_bypass_mode),
    .value_i             (adaptp_event_cnt),
    .value_o             (adaptp_hi_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_adaptp_hi (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_hi_fail_pulse),
    .value_o             (adaptp_hi_total_fails)
  );


  assign hw2reg.adaptp_hi_watermarks.fips_watermark.d = adaptp_hi_event_hwm_fips;
  assign hw2reg.adaptp_hi_watermarks.bypass_watermark.d = adaptp_hi_event_hwm_bypass;
  assign hw2reg.adaptp_hi_total_fails.d = adaptp_hi_total_fails;


  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_adaptp_lo_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_lo_fail_pulse && !es_bypass_mode),
    .value_i             (adaptp_event_cnt),
    .value_o             (adaptp_lo_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_adaptp_lo_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_lo_fail_pulse && es_bypass_mode),
    .value_i             (adaptp_event_cnt),
    .value_o             (adaptp_lo_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_adaptp_lo (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_lo_fail_pulse),
    .value_o             (adaptp_lo_total_fails)
  );

  assign hw2reg.adaptp_lo_watermarks.fips_watermark.d = adaptp_lo_event_hwm_fips;
  assign hw2reg.adaptp_lo_watermarks.bypass_watermark.d = adaptp_lo_event_hwm_bypass;
  assign hw2reg.adaptp_lo_total_fails.d = adaptp_lo_total_fails;


  //--------------------------------------------
  // bucket test
  //--------------------------------------------

  entropy_src_bucket_ht #(
    .RegWidth(HalfRegWidth),
    .RngBusWidth(RngBusWidth)
  ) u_entropy_src_bucket_ht (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .entropy_bit_i       (health_test_esbus),
    .entropy_bit_vld_i   (health_test_esbus_vld),
    .clear_i             (health_test_clr),
    .active_i            (bucket_active),
    .thresh_i            (bucket_threshold),
    .window_wrap_pulse_i (health_test_done_pulse),
    .test_cnt_o          (bucket_event_cnt),
    .test_fail_pulse_o   (bucket_fail_pulse)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_bucket_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (bucket_active),
    .event_i             (bucket_fail_pulse && !es_bypass_mode),
    .value_i             (bucket_event_cnt),
    .value_o             (bucket_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_bucket_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (bucket_active),
    .event_i             (bucket_fail_pulse && es_bypass_mode),
    .value_i             (bucket_event_cnt),
    .value_o             (bucket_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_bucket (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (bucket_active),
    .event_i             (bucket_fail_pulse),
    .value_o             (bucket_total_fails)
  );

  assign hw2reg.bucket_hi_watermarks.fips_watermark.d = bucket_event_hwm_fips;
  assign hw2reg.bucket_hi_watermarks.bypass_watermark.d = bucket_event_hwm_bypass;
  assign hw2reg.bucket_total_fails.d = bucket_total_fails;


  //--------------------------------------------
  // Markov test
  //--------------------------------------------

  entropy_src_markov_ht #(
    .RegWidth(HalfRegWidth),
    .RngBusWidth(RngBusWidth)
  ) u_entropy_src_markov_ht (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .entropy_bit_i       (health_test_esbus),
    .entropy_bit_vld_i   (health_test_esbus_vld),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .thresh_hi_i         (markov_hi_threshold),
    .thresh_lo_i         (markov_lo_threshold),
    .window_wrap_pulse_i (health_test_done_pulse),
    .test_cnt_hi_o       (markov_hi_event_cnt),
    .test_cnt_lo_o       (markov_lo_event_cnt),
    .test_fail_hi_pulse_o (markov_hi_fail_pulse),
    .test_fail_lo_pulse_o (markov_lo_fail_pulse)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_markov_hi_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_hi_fail_pulse && !es_bypass_mode),
    .value_i             (markov_hi_event_cnt),
    .value_o             (markov_hi_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_markov_hi_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_hi_fail_pulse && es_bypass_mode),
    .value_i             (markov_hi_event_cnt),
    .value_o             (markov_hi_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_markov_hi (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_hi_fail_pulse),
    .value_o             (markov_hi_total_fails)
  );

  assign hw2reg.markov_hi_watermarks.fips_watermark.d = markov_hi_event_hwm_fips;
  assign hw2reg.markov_hi_watermarks.bypass_watermark.d = markov_hi_event_hwm_bypass;
  assign hw2reg.markov_hi_total_fails.d = markov_hi_total_fails;


  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_markov_lo_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_lo_fail_pulse && !es_bypass_mode),
    .value_i             (markov_lo_event_cnt),
    .value_o             (markov_lo_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_markov_lo_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_lo_fail_pulse && es_bypass_mode),
    .value_i             (markov_lo_event_cnt),
    .value_o             (markov_lo_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_markov_lo (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (markov_active),
    .event_i             (markov_lo_fail_pulse),
    .value_o             (markov_lo_total_fails)
  );

  assign hw2reg.markov_lo_watermarks.fips_watermark.d = markov_lo_event_hwm_fips;
  assign hw2reg.markov_lo_watermarks.bypass_watermark.d = markov_lo_event_hwm_bypass;
  assign hw2reg.markov_lo_total_fails.d = markov_lo_total_fails;


  //--------------------------------------------
  // External health test
  //--------------------------------------------

  // set outputs to external health test
  assign entropy_src_xht_o.entropy_bit = health_test_esbus;
  assign entropy_src_xht_o.entropy_bit_valid = health_test_esbus_vld;
  assign entropy_src_xht_o.clear = health_test_clr;
  assign entropy_src_xht_o.active = extht_active;
  assign entropy_src_xht_o.thresh_hi = extht_hi_threshold;
  assign entropy_src_xht_o.thresh_lo = extht_lo_threshold;
  assign entropy_src_xht_o.window = health_test_window;
  // get inputs from external health test
  assign extht_event_cnt = entropy_src_xht_i.test_cnt;
  assign extht_hi_fail_pulse = entropy_src_xht_i.test_fail_hi_pulse;
  assign extht_lo_fail_pulse = entropy_src_xht_i.test_fail_lo_pulse;



  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_extht_hi_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_hi_fail_pulse && !es_bypass_mode),
    .value_i             (extht_event_cnt),
    .value_o             (extht_hi_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(1)
  ) u_entropy_src_watermark_reg_extht_hi_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_hi_fail_pulse && es_bypass_mode),
    .value_i             (extht_event_cnt),
    .value_o             (extht_hi_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_extht_hi (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_hi_fail_pulse),
    .value_o             (extht_hi_total_fails)
  );


  assign hw2reg.extht_hi_watermarks.fips_watermark.d = extht_hi_event_hwm_fips;
  assign hw2reg.extht_hi_watermarks.bypass_watermark.d = extht_hi_event_hwm_bypass;
  assign hw2reg.extht_hi_total_fails.d = extht_hi_total_fails;


  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_extht_lo_fips (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_lo_fail_pulse && !es_bypass_mode),
    .value_i             (extht_event_cnt),
    .value_o             (extht_lo_event_hwm_fips)
  );

  entropy_src_watermark_reg #(
    .RegWidth(HalfRegWidth),
    .HighWatermark(0)
  ) u_entropy_src_watermark_reg_extht_lo_bypass (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_lo_fail_pulse && es_bypass_mode),
    .value_i             (extht_event_cnt),
    .value_o             (extht_lo_event_hwm_bypass)
  );

  entropy_src_cntr_reg #(
    .RegWidth(FullRegWidth)
  ) u_entropy_src_cntr_reg_extht_lo (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (health_test_clr),
    .active_i            (extht_active),
    .event_i             (extht_lo_fail_pulse),
    .value_o             (extht_lo_total_fails)
  );

  assign hw2reg.extht_lo_watermarks.fips_watermark.d = extht_lo_event_hwm_fips;
  assign hw2reg.extht_lo_watermarks.bypass_watermark.d = extht_lo_event_hwm_bypass;
  assign hw2reg.extht_lo_total_fails.d = extht_lo_total_fails;


  //--------------------------------------------
  // summary and alert registers
  //--------------------------------------------

  assign alert_cntrs_clr = health_test_clr || rst_alert_cntr;

  entropy_src_cntr_reg #(
    .RegWidth(HalfRegWidth)
  ) u_entropy_src_cntr_reg_any_alert_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (any_active),
    .event_i             (any_fail_pulse),
    .value_o             (any_fail_count)
  );

  assign any_active = repcnt_active || repcnts_active || adaptp_active ||
         bucket_active || markov_active || extht_active;

  assign any_fail_pulse =
         repcnt_fail_pulse ||
         repcnts_fail_pulse ||
         adaptp_hi_fail_pulse || adaptp_lo_fail_pulse ||
         bucket_fail_pulse ||
         markov_hi_fail_pulse ||markov_lo_fail_pulse ||
         extht_hi_fail_pulse || extht_lo_fail_pulse;

  assign ht_failed_d =
         (!es_enable) ? 1'b0 :
         sfifo_esfinal_push ? 1'b0 :
         (any_fail_pulse && health_test_done_pulse) ? 1'b1 :
         ht_failed_q;


  // delay health pulse and fail pulse so that main_sm will
  // get the correct threshold value comparisons
  assign ht_done_pulse_d = health_test_done_pulse;
  assign ht_failed_pulse_d = any_fail_pulse;

  assign hw2reg.alert_summary_fail_counts.d = any_fail_count;

  // signal an alert
  assign alert_threshold = reg2hw.alert_threshold.alert_threshold.q;
  assign alert_threshold_inv = reg2hw.alert_threshold.alert_threshold_inv.q;

  assign alert_threshold_fail =
         ((any_fail_count >= ~alert_threshold_inv) && (~alert_threshold_inv != '0)) ||
         (any_fail_count >= alert_threshold) && (alert_threshold != '0);

  assign recov_alert_event = es_main_sm_alert;

  assign recov_alert_o = recov_alert_event;


  // repcnt fail counter
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_repcnt_alert_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (repcnt_active),
    .event_i             (repcnt_fail_pulse),
    .value_o             (repcnt_fail_count)
  );

  assign hw2reg.alert_fail_counts.repcnt_fail_count.d = repcnt_fail_count;

  // repcnts fail counter
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_repcnts_alert_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (repcnts_active),
    .event_i             (repcnts_fail_pulse),
    .value_o             (repcnts_fail_count)
  );

  assign hw2reg.alert_fail_counts.repcnts_fail_count.d = repcnts_fail_count;

  // adaptp fail counter hi and lo
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_adaptp_alert_hi_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_hi_fail_pulse),
    .value_o             (adaptp_hi_fail_count)
  );

  assign hw2reg.alert_fail_counts.adaptp_hi_fail_count.d = adaptp_hi_fail_count;

  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_adaptp_alert_lo_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (adaptp_active),
    .event_i             (adaptp_lo_fail_pulse),
    .value_o             (adaptp_lo_fail_count)
  );

  assign hw2reg.alert_fail_counts.adaptp_lo_fail_count.d = adaptp_lo_fail_count;

  // bucket fail counter
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_bucket_alert_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (bucket_active),
    .event_i             (bucket_fail_pulse),
    .value_o             (bucket_fail_count)
  );

  assign hw2reg.alert_fail_counts.bucket_fail_count.d = bucket_fail_count;


  // markov fail counter hi and lo
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_markov_alert_hi_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (markov_active),
    .event_i             (markov_hi_fail_pulse),
    .value_o             (markov_hi_fail_count)
  );

  assign hw2reg.alert_fail_counts.markov_hi_fail_count.d = markov_hi_fail_count;

  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_markov_alert_lo_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (markov_active),
    .event_i             (markov_lo_fail_pulse),
    .value_o             (markov_lo_fail_count)
  );

  assign hw2reg.alert_fail_counts.markov_lo_fail_count.d = markov_lo_fail_count;

  // extht fail counter hi and lo
  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_extht_alert_hi_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (extht_active),
    .event_i             (extht_hi_fail_pulse),
    .value_o             (extht_hi_fail_count)
  );

  assign hw2reg.extht_fail_counts.extht_hi_fail_count.d = extht_hi_fail_count;

  entropy_src_cntr_reg #(
    .RegWidth(EighthRegWidth)
  ) u_entropy_src_cntr_reg_extht_alert_lo_fails (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .clear_i             (alert_cntrs_clr),
    .active_i            (extht_active),
    .event_i             (extht_lo_fail_pulse),
    .value_o             (extht_lo_fail_count)
  );

  assign hw2reg.extht_fail_counts.extht_lo_fail_count.d = extht_lo_fail_count;

  //--------------------------------------------
  // pack tested entropy into 32 bit packer
  //--------------------------------------------

  prim_packer_fifo #(
    .InW(RngBusWidth),
    .OutW(PostHTWidth)
  ) u_prim_packer_fifo_postht (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (pfifo_postht_clr),
    .wvalid_i   (pfifo_postht_push),
    .wdata_i    (pfifo_postht_wdata),
    .wready_o   (),
    .rvalid_o   (pfifo_postht_not_empty),
    .rdata_o    (pfifo_postht_rdata),
    .rready_i   (pfifo_postht_pop),
    .depth_o    ()
  );

  assign pfifo_postht_push = ht_esbus_vld_dly_q;
  assign pfifo_postht_wdata = ht_esbus_dly_q;

  assign pfifo_postht_clr = !es_enable;
  assign pfifo_postht_pop = ht_esbus_vld_dly2_q &&
         pfifo_postht_not_empty;


  //--------------------------------------------
  // store entropy into a 64 entry deep FIFO
  //--------------------------------------------

  prim_fifo_sync #(
    .Width(ObserveFifoWidth),
    .Pass(0),
    .Depth(ObserveFifoDepth)
  ) u_prim_fifo_sync_observe (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (sfifo_observe_clr),
    .wvalid_i   (sfifo_observe_push),
    .wdata_i    (sfifo_observe_wdata),
    .wready_o   (),
    .rvalid_o   (sfifo_observe_not_empty),
    .rdata_o    (sfifo_observe_rdata),
    .rready_i   (sfifo_observe_pop),
    .full_o     (sfifo_observe_full),
    .depth_o    (sfifo_observe_depth)
  );


  assign observe_fifo_thresh_met = fw_ov_mode && (observe_fifo_thresh <= sfifo_observe_depth);

  // fifo controls
  assign sfifo_observe_push = fw_ov_mode && pfifo_postht_pop;

  assign sfifo_observe_clr  = !es_enable;

  assign sfifo_observe_wdata = pfifo_postht_rdata;

  assign sfifo_observe_pop =
         (fw_ov_mode &&
          (fw_ov_fifo_rd_pulse ||
           ((Clog2ObserveFifoDepth+1)'(ObserveFifoDepth-1) == sfifo_observe_depth)));

  // fifo err
  assign sfifo_observe_err =
         {1'b0,
         (sfifo_observe_pop && !sfifo_observe_not_empty),
         (sfifo_observe_full && !sfifo_observe_not_empty)};


  //--------------------------------------------
  // pack entropy into 64 bit packer
  //--------------------------------------------

  prim_packer_fifo #(
    .InW(ObserveFifoWidth),
    .OutW(PreCondWidth)
  ) u_prim_packer_fifo_precon (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (pfifo_precon_clr),
    .wvalid_i   (pfifo_precon_push),
    .wdata_i    (pfifo_precon_wdata),
    .wready_o   (),
    .rvalid_o   (pfifo_precon_not_empty),
    .rdata_o    (pfifo_precon_rdata),
    .rready_i   (pfifo_precon_pop),
    .depth_o    ()
  );

  assign pfifo_precon_push = fw_ov_mode ?
         (fw_ov_entropy_insert ? fw_ov_fifo_wr_pulse : pfifo_postht_pop) :
         pfifo_postht_pop;

  assign pfifo_precon_wdata = fw_ov_mode ?
         (fw_ov_entropy_insert ? fw_ov_wr_data : pfifo_postht_rdata) :
         pfifo_postht_rdata;

  assign pfifo_precon_clr = !es_enable;
  assign pfifo_precon_pop = pfifo_precon_not_empty;


  //--------------------------------------------
  // entropy conditioner
  //--------------------------------------------
  // This block will take in raw entropy from the noise source block
  // and compress it such that a perfect entropy source is created
  // This block will take in 2048 (by default setting) bits to create 384 bits.


  assign pfifo_cond_push = pfifo_precon_pop && sha3_msgfifo_ready &&
  !cs_aes_halt_req && !es_bypass_mode;

  assign pfifo_cond_wdata = pfifo_precon_rdata;

  assign msg_data[0] = pfifo_cond_wdata;

  assign pfifo_cond_rdata = sha3_state[0][SeedLen-1:0];
  assign pfifo_cond_not_empty = sha3_state_vld;
  assign sha3_msgfifo_ready = sha3_msg_rdy_q;

  assign sha3_msg_rdy_d = es_enable && sha3_msg_rdy;

  // SHA3 hashing engine
  sha3 #(
    .EnMasking (Sha3EnMasking),
    .ReuseShare (Sha3ReuseShare)
  ) u_sha3 (
    .clk_i,
    .rst_ni,

    // MSG_FIFO interface
    .msg_valid_i (pfifo_cond_push),
    .msg_data_i  (msg_data),
    .msg_strb_i  ({8{pfifo_cond_push}}),
    .msg_ready_o (sha3_msg_rdy),

    // Entropy interface - not using
    .rand_valid_i    (1'b0),
    .rand_data_i     ('0),
    .rand_consumed_o (),

    // N, S: Used in cSHAKE mode
    .ns_data_i       ('0), // ns_prefix),

    // Configurations
    .mode_i     (sha3_pkg::Sha3), // Use SHA3 mode
    .strength_i (sha3_pkg::L384), // Use keccak_strength_e of L384

    // Controls (CMD register)
    .start_i    (sha3_start       ),
    .process_i  (sha3_process     ),
    .run_i      (1'b0             ), // For software application
    .done_i     (sha3_done        ),

    .absorbed_o (sha3_absorbed),
    .squeezing_o (sha3_squeezing),

    .block_processed_o (sha3_block_processed),

    .sha3_fsm_o (sha3_fsm),

    .state_valid_o (sha3_state_vld),
    .state_o       (sha3_state),

    .error_o (sha3_err)
  );


  //--------------------------------------------
  // bypass SHA conditioner path
  //--------------------------------------------

  prim_packer_fifo #(
     .InW(PreCondWidth),
     .OutW(SeedLen)
  ) u_prim_packer_fifo_bypass (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (pfifo_bypass_clr),
    .wvalid_i   (pfifo_bypass_push),
    .wdata_i    (pfifo_bypass_wdata),
    .wready_o   (),
    .rvalid_o   (pfifo_bypass_not_empty),
    .rdata_o    (pfifo_bypass_rdata),
    .rready_i   (pfifo_bypass_pop),
    .depth_o    ()
  );

  assign pfifo_bypass_push = pfifo_precon_pop && es_bypass_mode;
  assign pfifo_bypass_wdata = pfifo_precon_rdata;

  assign pfifo_bypass_clr = !es_enable;
  assign pfifo_bypass_pop = bypass_stage_pop;


  // mux to select between fips and bypass mode
  assign final_es_data = es_bypass_mode ? pfifo_bypass_rdata : pfifo_cond_rdata;


  //--------------------------------------------
  // state machine to coordinate fifo flow
  //--------------------------------------------

  entropy_src_main_sm
    u_entropy_src_main_sm (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .enable_i             (es_enable),
    .ht_done_pulse_i      (ht_done_pulse_q),
    .ht_fail_pulse_i      (ht_failed_pulse_q),
    .alert_thresh_fail_i  (alert_threshold_fail),
    .sfifo_esfinal_full_i (sfifo_esfinal_full),
    .rst_alert_cntr_o     (rst_alert_cntr),
    .bypass_mode_i        (es_bypass_mode),
    .rst_bypass_mode_o    (rst_bypass_mode),
    .main_stage_rdy_i     (pfifo_cond_not_empty),
    .bypass_stage_rdy_i   (pfifo_bypass_not_empty),
    .sha3_state_vld_i     (sha3_state_vld),
    .main_stage_pop_o     (main_stage_pop),
    .bypass_stage_pop_o   (bypass_stage_pop),
    .sha3_start_o         (sha3_start),
    .sha3_process_o       (sha3_process),
    .sha3_done_o          (sha3_done),
    .cs_aes_halt_req_o    (cs_aes_halt_req),
    .cs_aes_halt_ack_i    (cs_aes_halt_i.cs_aes_halt_ack),
    .main_sm_alert_o      (es_main_sm_alert),
    .main_sm_idle_o       (es_main_sm_idle),
    .main_sm_state_o      (es_main_sm_state),
    .main_sm_err_o        (es_main_sm_err)
  );

  // es to cs halt request to reduce power spikes
  // assign cs_aes_halt_d = es_enable && cs_aes_halt_req;
  assign cs_aes_halt_d = cs_aes_halt_req;
  assign cs_aes_halt_o.cs_aes_halt_req = cs_aes_halt_q;

  //--------------------------------------------
  // send processed entropy to final fifo
  //--------------------------------------------

  prim_fifo_sync #(
    .Width(1+SeedLen),
    .Pass(0),
    .Depth(EsFifoDepth)
  ) u_prim_fifo_sync_esfinal (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .clr_i          (sfifo_esfinal_clr),
    .wvalid_i       (sfifo_esfinal_push),
    .wready_o       (sfifo_esfinal_not_full),
    .wdata_i        (sfifo_esfinal_wdata),
    .rvalid_o       (sfifo_esfinal_not_empty),
    .rready_i       (sfifo_esfinal_pop),
    .rdata_o        (sfifo_esfinal_rdata),
    .full_o         (sfifo_esfinal_full),
    .depth_o        (sfifo_esfinal_depth)
  );

  assign fips_compliance = !es_bypass_mode && es_enable_rng && !es_enable_lfsr && !rng_bit_en;

  // fifo controls
  assign sfifo_esfinal_push = sfifo_esfinal_not_full &&
         ((main_stage_pop || bypass_stage_pop) && !ht_failed_q);
  assign sfifo_esfinal_clr  = !es_enable;
  assign sfifo_esfinal_wdata = {fips_compliance,final_es_data};
  assign sfifo_esfinal_pop = es_route_to_sw ? pfifo_swread_push :
         es_hw_if_fifo_pop;
  assign {esfinal_fips_flag,esfinal_data} = sfifo_esfinal_rdata;

  // fifo err
  assign sfifo_esfinal_err =
         {(sfifo_esfinal_push && sfifo_esfinal_full),
          (sfifo_esfinal_pop && !sfifo_esfinal_not_empty),
          (sfifo_esfinal_full && !sfifo_esfinal_not_empty)};

  // drive out hw interface
  assign es_hw_if_req = entropy_src_hw_if_i.es_req;
  assign entropy_src_hw_if_o.es_ack = es_hw_if_ack;
  assign entropy_src_hw_if_o.es_bits = esfinal_data;
  assign entropy_src_hw_if_o.es_fips = esfinal_fips_flag;

  entropy_src_ack_sm u_entropy_src_ack_sm (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .enable_i         (es_enable),
    .req_i            (es_hw_if_req),
    .ack_o            (es_hw_if_ack),
    .fifo_not_empty_i (sfifo_esfinal_not_empty && !es_route_to_sw),
    .fifo_pop_o       (es_hw_if_fifo_pop),
    .ack_sm_err_o     (es_ack_sm_err)
  );

  //--------------------------------------------
  // software es read path
  //--------------------------------------------

  prim_packer_fifo #(
    .InW(SeedLen),
    .OutW(FullRegWidth)
  ) u_prim_packer_fifo_swread (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .clr_i      (pfifo_swread_clr),
    .wvalid_i   (pfifo_swread_push),
    .wdata_i    (pfifo_swread_wdata),
    .wready_o   (pfifo_swread_not_full),
    .rvalid_o   (pfifo_swread_not_empty),
    .rdata_o    (pfifo_swread_rdata),
    .rready_i   (pfifo_swread_pop),
    .depth_o    ()
  );

  assign pfifo_swread_push = es_route_to_sw && pfifo_swread_not_full && sfifo_esfinal_not_empty;
  assign pfifo_swread_wdata = esfinal_data;

  assign pfifo_swread_clr = !es_enable;
  assign pfifo_swread_pop =  es_enable && sw_es_rd_pulse;

  // set the es entropy to the read reg
  assign hw2reg.entropy_data.d = es_enable ? pfifo_swread_rdata : '0;
  assign sw_es_rd_pulse = efuse_es_sw_reg_en_i && reg2hw.entropy_data.re;

  //--------------------------------------------
  // unused signals
  //--------------------------------------------

  assign unused_err_code_test_bit = (|{err_code_test_bit[27:22],err_code_test_bit[19:3]});
  assign unused_sha3_state = (|sha3_state[0][sha3_pkg::StateW-1:SeedLen]);
  assign unused_entropy_data = (|reg2hw.entropy_data.q);
  assign unused_fw_ov_rd_data = (|reg2hw.fw_ov_rd_data.q);


endmodule
