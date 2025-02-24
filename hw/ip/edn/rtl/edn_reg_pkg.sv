// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Register Package auto-generated by `reggen` containing data structure

package edn_reg_pkg;

  // Param list
  parameter int NumAlerts = 1;

  // Address widths within the block
  parameter int BlockAw = 6;

  ////////////////////////////
  // Typedefs for registers //
  ////////////////////////////

  typedef struct packed {
    struct packed {
      logic        q;
    } edn_cmd_req_done;
    struct packed {
      logic        q;
    } edn_fatal_err;
  } edn_reg2hw_intr_state_reg_t;

  typedef struct packed {
    struct packed {
      logic        q;
    } edn_cmd_req_done;
    struct packed {
      logic        q;
    } edn_fatal_err;
  } edn_reg2hw_intr_enable_reg_t;

  typedef struct packed {
    struct packed {
      logic        q;
      logic        qe;
    } edn_cmd_req_done;
    struct packed {
      logic        q;
      logic        qe;
    } edn_fatal_err;
  } edn_reg2hw_intr_test_reg_t;

  typedef struct packed {
    logic        q;
    logic        qe;
  } edn_reg2hw_alert_test_reg_t;

  typedef struct packed {
    struct packed {
      logic [3:0]  q;
    } edn_enable;
    struct packed {
      logic [3:0]  q;
    } boot_req_mode;
    struct packed {
      logic [3:0]  q;
    } auto_req_mode;
    struct packed {
      logic [3:0]  q;
    } cmd_fifo_rst;
  } edn_reg2hw_ctrl_reg_t;

  typedef struct packed {
    logic [31:0] q;
    logic        qe;
  } edn_reg2hw_sw_cmd_req_reg_t;

  typedef struct packed {
    logic [31:0] q;
    logic        qe;
  } edn_reg2hw_reseed_cmd_reg_t;

  typedef struct packed {
    logic [31:0] q;
    logic        qe;
  } edn_reg2hw_generate_cmd_reg_t;

  typedef struct packed {
    logic [31:0] q;
    logic        qe;
  } edn_reg2hw_max_num_reqs_between_reseeds_reg_t;

  typedef struct packed {
    logic [4:0]  q;
    logic        qe;
  } edn_reg2hw_err_code_test_reg_t;

  typedef struct packed {
    struct packed {
      logic        d;
      logic        de;
    } edn_cmd_req_done;
    struct packed {
      logic        d;
      logic        de;
    } edn_fatal_err;
  } edn_hw2reg_intr_state_reg_t;

  typedef struct packed {
    struct packed {
      logic        d;
      logic        de;
    } req_mode_sm_sts;
    struct packed {
      logic        d;
      logic        de;
    } boot_inst_ack;
  } edn_hw2reg_sum_sts_reg_t;

  typedef struct packed {
    struct packed {
      logic        d;
      logic        de;
    } cmd_rdy;
    struct packed {
      logic        d;
      logic        de;
    } cmd_sts;
  } edn_hw2reg_sw_cmd_sts_reg_t;

  typedef struct packed {
    struct packed {
      logic        d;
      logic        de;
    } sfifo_rescmd_err;
    struct packed {
      logic        d;
      logic        de;
    } sfifo_gencmd_err;
    struct packed {
      logic        d;
      logic        de;
    } edn_ack_sm_err;
    struct packed {
      logic        d;
      logic        de;
    } edn_main_sm_err;
    struct packed {
      logic        d;
      logic        de;
    } fifo_write_err;
    struct packed {
      logic        d;
      logic        de;
    } fifo_read_err;
    struct packed {
      logic        d;
      logic        de;
    } fifo_state_err;
  } edn_hw2reg_err_code_reg_t;

  // Register -> HW type
  typedef struct packed {
    edn_reg2hw_intr_state_reg_t intr_state; // [163:162]
    edn_reg2hw_intr_enable_reg_t intr_enable; // [161:160]
    edn_reg2hw_intr_test_reg_t intr_test; // [159:156]
    edn_reg2hw_alert_test_reg_t alert_test; // [155:154]
    edn_reg2hw_ctrl_reg_t ctrl; // [153:138]
    edn_reg2hw_sw_cmd_req_reg_t sw_cmd_req; // [137:105]
    edn_reg2hw_reseed_cmd_reg_t reseed_cmd; // [104:72]
    edn_reg2hw_generate_cmd_reg_t generate_cmd; // [71:39]
    edn_reg2hw_max_num_reqs_between_reseeds_reg_t max_num_reqs_between_reseeds; // [38:6]
    edn_reg2hw_err_code_test_reg_t err_code_test; // [5:0]
  } edn_reg2hw_t;

  // HW -> register type
  typedef struct packed {
    edn_hw2reg_intr_state_reg_t intr_state; // [25:22]
    edn_hw2reg_sum_sts_reg_t sum_sts; // [21:18]
    edn_hw2reg_sw_cmd_sts_reg_t sw_cmd_sts; // [17:14]
    edn_hw2reg_err_code_reg_t err_code; // [13:0]
  } edn_hw2reg_t;

  // Register offsets
  parameter logic [BlockAw-1:0] EDN_INTR_STATE_OFFSET = 6'h 0;
  parameter logic [BlockAw-1:0] EDN_INTR_ENABLE_OFFSET = 6'h 4;
  parameter logic [BlockAw-1:0] EDN_INTR_TEST_OFFSET = 6'h 8;
  parameter logic [BlockAw-1:0] EDN_ALERT_TEST_OFFSET = 6'h c;
  parameter logic [BlockAw-1:0] EDN_REGWEN_OFFSET = 6'h 10;
  parameter logic [BlockAw-1:0] EDN_CTRL_OFFSET = 6'h 14;
  parameter logic [BlockAw-1:0] EDN_SUM_STS_OFFSET = 6'h 18;
  parameter logic [BlockAw-1:0] EDN_SW_CMD_REQ_OFFSET = 6'h 1c;
  parameter logic [BlockAw-1:0] EDN_SW_CMD_STS_OFFSET = 6'h 20;
  parameter logic [BlockAw-1:0] EDN_RESEED_CMD_OFFSET = 6'h 24;
  parameter logic [BlockAw-1:0] EDN_GENERATE_CMD_OFFSET = 6'h 28;
  parameter logic [BlockAw-1:0] EDN_MAX_NUM_REQS_BETWEEN_RESEEDS_OFFSET = 6'h 2c;
  parameter logic [BlockAw-1:0] EDN_ERR_CODE_OFFSET = 6'h 30;
  parameter logic [BlockAw-1:0] EDN_ERR_CODE_TEST_OFFSET = 6'h 34;

  // Reset values for hwext registers and their fields
  parameter logic [1:0] EDN_INTR_TEST_RESVAL = 2'h 0;
  parameter logic [0:0] EDN_INTR_TEST_EDN_CMD_REQ_DONE_RESVAL = 1'h 0;
  parameter logic [0:0] EDN_INTR_TEST_EDN_FATAL_ERR_RESVAL = 1'h 0;
  parameter logic [0:0] EDN_ALERT_TEST_RESVAL = 1'h 0;
  parameter logic [0:0] EDN_ALERT_TEST_FATAL_ALERT_RESVAL = 1'h 0;
  parameter logic [31:0] EDN_SW_CMD_REQ_RESVAL = 32'h 0;
  parameter logic [31:0] EDN_RESEED_CMD_RESVAL = 32'h 0;
  parameter logic [31:0] EDN_GENERATE_CMD_RESVAL = 32'h 0;

  // Register index
  typedef enum int {
    EDN_INTR_STATE,
    EDN_INTR_ENABLE,
    EDN_INTR_TEST,
    EDN_ALERT_TEST,
    EDN_REGWEN,
    EDN_CTRL,
    EDN_SUM_STS,
    EDN_SW_CMD_REQ,
    EDN_SW_CMD_STS,
    EDN_RESEED_CMD,
    EDN_GENERATE_CMD,
    EDN_MAX_NUM_REQS_BETWEEN_RESEEDS,
    EDN_ERR_CODE,
    EDN_ERR_CODE_TEST
  } edn_id_e;

  // Register width information to check illegal writes
  parameter logic [3:0] EDN_PERMIT [14] = '{
    4'b 0001, // index[ 0] EDN_INTR_STATE
    4'b 0001, // index[ 1] EDN_INTR_ENABLE
    4'b 0001, // index[ 2] EDN_INTR_TEST
    4'b 0001, // index[ 3] EDN_ALERT_TEST
    4'b 0001, // index[ 4] EDN_REGWEN
    4'b 0011, // index[ 5] EDN_CTRL
    4'b 0001, // index[ 6] EDN_SUM_STS
    4'b 1111, // index[ 7] EDN_SW_CMD_REQ
    4'b 0001, // index[ 8] EDN_SW_CMD_STS
    4'b 1111, // index[ 9] EDN_RESEED_CMD
    4'b 1111, // index[10] EDN_GENERATE_CMD
    4'b 1111, // index[11] EDN_MAX_NUM_REQS_BETWEEN_RESEEDS
    4'b 1111, // index[12] EDN_ERR_CODE
    4'b 0001  // index[13] EDN_ERR_CODE_TEST
  };

endpackage

