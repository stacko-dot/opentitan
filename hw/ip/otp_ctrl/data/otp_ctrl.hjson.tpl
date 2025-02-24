// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// HJSON with partition metadata.
//
// DO NOT EDIT THIS FILE DIRECTLY.
// It has been generated with ./util/design/gen-otp-mmap.py

<%
  num_part = len(otp_mmap.config["partitions"])

  def PascalCase(inp):
    oup = ''
    upper = True
    for k in inp.lower():
      if k == '_':
        upper = True
      else:
        oup += k.upper() if upper else k
        upper = False
    return oup
%>
{ name: "otp_ctrl",
  clocking: [
    {clock: "clk_i", reset: "rst_ni", primary: true},
    {clock: "clk_edn_i", reset: "rst_edn_ni"}
  ]
  scan: "true",       // Enable `scanmode_i` port
  scan_reset: "true", // Enable `scan_rst_ni` port
  scan_en: "true",    // Enable `scan_en_i` port
  bus_interfaces: [
    { protocol: "tlul", direction: "device", name: "core" }
    { protocol: "tlul", direction: "device", name: "prim" }
  ],

  available_output_list: [
    { name: "test",
      width: 8,
      desc: "Test-related GPIOs. Only active in DFT-enabled life cycle states."
    }
  ],

  ///////////////////////////
  // Interrupts and Alerts //
  ///////////////////////////

  interrupt_list: [
    { name: "otp_operation_done",
      desc: "A direct access command or digest calculation operation has completed."
    }
    { name: "otp_error",
      desc: "An error has occurred in the OTP controller. Check the !!ERR_CODE register to get more information."
    }
  ],

  alert_list: [
    { name: "fatal_macro_error",
      desc: "This alert triggers if hardware detects an ECC or digest error in the buffered partitions.",
    }
    { name: "fatal_check_error",
      desc: "This alert triggers if the digest over the buffered registers does not match with the digest stored in OTP.",
    }
    { name: "fatal_bus_integ_error",
      desc: "This fatal alert is triggered when a fatal TL-UL bus integrity fault is detected."
    }
  ],

  ////////////////
  // Parameters //
  ////////////////
  param_list: [
    // Init file
    { name:      "MemInitFile",
      desc:      "VMEM file to initialize the OTP macro.",
      type:      "",
      default:   '""',
      expose:    "true",
      local:     "false"
    }
    // Random netlist constants
    { name:      "RndCnstLfsrSeed",
      desc:      "Compile-time random bits for initial LFSR seed",
      type:      "otp_ctrl_pkg::lfsr_seed_t"
      randcount: "40",
      randtype:  "data", // randomize randcount databits
    }
    { name:      "RndCnstLfsrPerm",
      desc:      "Compile-time random permutation for LFSR output",
      type:      "otp_ctrl_pkg::lfsr_perm_t"
      randcount: "40",
      randtype:  "perm", // random permutation for randcount elements
    }
    // Normal parameters
    { name: "NumSramKeyReqSlots",
      desc: "Number of key slots",
      type: "int",
      default: "2",
      local: "true"
    },
    { name: "OtpByteAddrWidth",
      desc: "Width of the OTP byte address.",
      type: "int",
      default: "${otp_mmap.config["otp"]["byte_addr_width"]}",
      local: "true"
    },
    { name: "NumErrorEntries",
      desc: "Number of error register entries.",
      type: "int",
      default: "${num_part + 2}", // partitions + DAI/LCI
      local: "true"
    },
    { name: "NumDaiWords",
      desc: "Number of 32bit words in the DAI.",
      type: "int",
      default: "2",
      local: "true"
    },
    { name: "NumDigestWords",
      desc: "Size of the digest fields in 32bit words.",
      type: "int",
      default: "2",
      local: "true"
    },
    { name: "NumSwCfgWindowWords",
      desc: "Size of the TL-UL window in 32bit words. Note that the effective partition size is smaller than that.",
      type: "int",
      default: "512",
      local: "true"
    },
    { name: "NumDebugWindowWords",
      desc: "Size of the TL-UL window in 32bit words.",
      type: "int",
      default: "16",
      local: "true"
    },

    // Memory map Info
    { name: "NumPart",
      desc: "Number of partitions",
      type: "int",
      default: "${num_part}",
      local: "true"
    },
% for part in otp_mmap.config["partitions"]:
    { name: "${PascalCase(part["name"])}Offset",
      desc: "Offset of the ${part["name"]} partition",
      type: "int",
      default: "${part["offset"]}",
      local: "true"
    },
    { name: "${PascalCase(part["name"])}Size",
      desc: "Size of the ${part["name"]} partition",
      type: "int",
      default: "${part["size"]}",
      local: "true"
    },
  % for item in part["items"]:
    { name: "${PascalCase(item["name"])}Offset",
      desc: "Offset of ${item["name"]}",
      type: "int",
      default: "${item["offset"]}",
      local: "true"
    },
    { name: "${PascalCase(item["name"])}Size",
      desc: "Size of ${item["name"]}",
      type: "int",
      default: "${item["size"]}",
      local: "true"
    },
  % endfor
% endfor
  ]

  /////////////////////////////
  // Intermodule Connections //
  /////////////////////////////

  inter_signal_list: [
    // Power sequencing signals to AST
    { struct:  "otp_ast_req"
      type:    "uni"
      name:    "otp_ast_pwr_seq"
      act:     "req"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Power sequencing signals from AST
    { struct:  "otp_ast_rsp"
      type:    "uni"
      name:    "otp_ast_pwr_seq_h"
      act:     "rcv"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // AST alert handling
    { struct:  "ast_dif"
      type:    "uni"
      name:    "otp_alert"
      act:     "req"
      package: "ast_pkg"
    }
    // EDN interface
    { struct:  "edn"
      type:    "req_rsp"
      name:    "edn"
      act:     "req"
      package: "edn_pkg"
    }
    // Power manager init command
    { struct:  "pwr_otp"
      type:    "req_rsp"
      name:    "pwr_otp"
      act:     "rsp"
      default: "'0"
      package: "pwrmgr_pkg"
    }
    // LC transition command
    { struct:  "lc_otp_program"
      type:    "req_rsp"
      name:    "lc_otp_program"
      act:     "rsp"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Broadcast to LC
    { struct:  "otp_lc_data"
      type:    "uni"
      name:    "otp_lc_data"
      act:     "req"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Broadcast from LC
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_escalate_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg"
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_creator_seed_sw_rw_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg"
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_seed_hw_rd_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg"
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_dft_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg"
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_check_byp_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg"
    }
    // Broadcast to Key Manager
    { struct:  "otp_keymgr_key"
      type:    "uni"
      name:    "otp_keymgr_key"
      act:     "req"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Broadcast to Flash Controller
    { struct:  "flash_otp_key"
      type:    "req_rsp"
      name:    "flash_otp_key"
      act:     "rsp"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Key request from SRAM scramblers
    { struct:  "sram_otp_key"
      // TODO: would be nice if this could accept parameters.
      // Split this out into an issue.
      width:   "2"
      type:    "req_rsp"
      name:    "sram_otp_key"
      act:     "rsp"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Key request from OTBN RAM Scrambler
    { struct:  "otbn_otp_key"
      type:    "req_rsp"
      name:    "otbn_otp_key"
      act:     "rsp"
      default: "'0"
      package: "otp_ctrl_pkg"
    }
    // Hardware config partition
    { struct:  "otp_hw_cfg"
      type:    "uni"
      name:    "otp_hw_cfg"
      act:     "req"
      default: "'0"
      package: "otp_ctrl_part_pkg"
    }
  ] // inter_signal_list

  regwidth: "32",
  registers: {
    core: [
      ////////////////////////
      // Ctrl / Status CSRs //
      ////////////////////////

      { name: "STATUS",
        desc: "OTP status register.",
        swaccess: "ro",
        hwaccess: "hwo",
        hwext:    "true",
        tags: [ // OTP internal HW can modify status register
                "excl:CsrAllTests:CsrExclCheck"],
        fields: [
  % for k, part in enumerate(otp_mmap.config["partitions"]):
          { bits: "${k}"
            name: "${part["name"]}_ERROR"
            desc: '''
                  Set to 1 if an error occurred in this partition.
                  If set to 1, SW should check the !!ERR_CODE register at the corresponding index.
                  '''
          }
  % endfor
          { bits: "${num_part}"
            name: "DAI_ERROR"
            desc: '''
                  Set to 1 if an error occurred in the DAI.
                  If set to 1, SW should check the !!ERR_CODE register at the corresponding index.
                  '''
          }
          { bits: "${num_part+1}"
            name: "LCI_ERROR"
            desc: '''
                  Set to 1 if an error occurred in the LCI.
                  If set to 1, SW should check the !!ERR_CODE register at the corresponding index.
                  '''
          }
          { bits: "${num_part+2}"
            name: "TIMEOUT_ERROR"
            desc: '''
                  Set to 1 if an integrity or consistency check times out.
                  This raises an fatal_check_error alert and is an unrecoverable error condition.
                  '''
          }
          { bits: "${num_part+3}"
            name: "LFSR_FSM_ERROR"
            desc: '''
                  Set to 1 if the LFSR timer FSM has reached an invalid state.
                  This raises an fatal_check_error alert and is an unrecoverable error condition.
                  '''
          }
          { bits: "${num_part+4}"
            name: "SCRAMBLING_FSM_ERROR"
            desc: '''
                  Set to 1 if the scrambling datapath FSM has reached an invalid state.
                  This raises an fatal_check_error alert and is an unrecoverable error condition.
                  '''
          }
          { bits: "${num_part+5}"
            name: "KEY_DERIV_FSM_ERROR"
            desc: '''
                  Set to 1 if the key derivation FSM has reached an invalid state.
                  This raises an fatal_check_error alert and is an unrecoverable error condition.
                  '''
          }
          { bits: "${num_part+6}"
            name: "BUS_INTEG_ERROR"
            desc: '''
                  This bit is set to 1 if a fatal bus integrity fault is detected.
                  This error triggers a fatal_bus_integ_error alert.
                  '''
          }
          { bits: "${num_part+7}"
            name: "DAI_IDLE"
            desc: "Set to 1 if the DAI is idle and ready to accept commands."
          }
          { bits: "${num_part+8}"
            name: "CHECK_PENDING"
            desc: "Set to 1 if an integrity or consistency check triggered by the LFSR timer or via !!CHECK_TRIGGER is pending."
          }
        ]
      }
      { multireg: {
          name:     "ERR_CODE",
          desc:     '''
                    This register holds information about error conditions that occurred in the agents
                    interacting with the OTP macro via the internal bus. The error codes should be checked
                    if the partitions, DAI or LCI flag an error in the !!STATUS register, or when an
                    !!INTR_STATE.otp_error has been triggered. Note that all errors trigger an otp_error
                    interrupt, and in addition some errors may trigger either an fatal_macro_error or an
                    fatal_check_error alert.
                    ''',
          count:     "NumErrorEntries",
          swaccess:  "ro",
          hwaccess:  "hwo",
          hwext:     "true",
          cname:     "AGENT",
          tags: [ // OTP internal HW can modify the error code registers
                  "excl:CsrAllTests:CsrExclCheck"],
          fields: [
            {
              bits: "2:0"
              enum: [
                { value: "0",
                  name: "NO_ERROR",
                  desc: '''
                  No error condition has occurred.
                  '''
                },
                { value: "1",
                  name: "MACRO_ERROR",
                  desc: '''
                  Returned if the OTP macro command was invalid or did not complete successfully
                  due to a macro malfunction.
                  This error should never occur during normal operation and is not recoverable.
                  This error triggers an fatal_macro_error alert.
                  '''
                },
                { value: "2",
                  name: "MACRO_ECC_CORR_ERROR",
                  desc: '''
                  A correctable ECC error has occured during an OTP read operation.
                  The corresponding controller automatically recovers from this error when
                  issuing a new command.
                  '''
                },
                { value: "3",
                  name: "MACRO_ECC_UNCORR_ERROR",
                  desc: '''
                  An uncorrectable ECC error has occurred during an OTP read operation.
                  This error should never occur during normal operation and is not recoverable.
                  If this error is present this may be a sign that the device is malfunctioning.
                  This error triggers an fatal_macro_error alert.
                  '''
                },
                { value: "4",
                  name: "MACRO_WRITE_BLANK_ERROR",
                  desc: '''
                  This error is returned if a programming operation attempted to clear a bit that has previously been programmed to 1.
                  The corresponding controller automatically recovers from this error when issuing a new command.

                  Note however that the affected OTP word may be left in an inconsistent state if this error occurs.
                  This can cause several issues when the word is accessed again (either as part of a regular read operation, as part of the readout at boot, or as part of a background check).

                  It is important that SW ensures that each word is only written once, since this can render the device useless.
                  '''
                },
                { value: "5",
                  name: "ACCESS_ERROR",
                  desc: '''
                  This error indicates that a locked memory region has been accessed.
                  The corresponding controller automatically recovers from this error when issuing a new command.
                  '''
                },
                { value: "6",
                  name: "CHECK_FAIL_ERROR",
                  desc: '''
                  An ECC, integrity or consistency mismatch has been detected in the buffer registers.
                  This error should never occur during normal operation and is not recoverable.
                  This error triggers an fatal_check_error alert.
                  '''
                },
                { value: "7",
                  name: "FSM_STATE_ERROR",
                  desc: '''
                  The FSM of the corresponding controller has reached an invalid state, or the FSM has
                  been moved into a terminal error state due to an escalation action via lc_escalate_en_i.
                  This error should never occur during normal operation and is not recoverable.
                  If this error is present, this is a sign that the device has fallen victim to
                  an invasive attack. This error triggers an fatal_check_error alert.
                  '''
                },
              ]
            }
          ]
        }
      }
      { name: "DIRECT_ACCESS_REGWEN",
        desc: '''
              Register write enable for all direct access interface registers.
              ''',
        swaccess: "ro",
        hwaccess: "hwo",
        hwext:    "true",
        tags: [ // OTP internal HW will set this enable register to 0 when OTP is not under IDLE
                // state, so could not auto-predict its value
                "excl:CsrNonInitTests:CsrExclCheck"],
        fields: [
          {
              bits:   "0",
              desc: ''' This bit is hardware-managed and only readable by software.
              The DAI sets this bit temporarily to 0 during an OTP operation such that
              the corresponding address and data registers cannot be modified while
              the operation is pending.
              '''
              resval: 1,
          },
        ]
      },
      { name: "DIRECT_ACCESS_CMD",
        desc: "Command register for direct accesses.",
        swaccess: "r0w1c",
        hwaccess: "hro",
        hwqe:     "true",
        hwext:    "true",
        regwen:   "DIRECT_ACCESS_REGWEN",
        tags: [ // Write to DIRECT_ACCESS_CMD randomly might cause OTP_ERRORs and illegal sequences
                "excl:CsrNonInitTests:CsrExclWrite"],
        fields: [
          { bits: "0",
            name: "RD",
            desc: '''
            Initiates a readout sequence that reads the location specified
            by !!DIRECT_ACCESS_ADDRESS. The command places the data read into
            !!DIRECT_ACCESS_RDATA_0 and !!DIRECT_ACCESS_RDATA_1 (for 64bit partitions).
            '''
          }
          { bits: "1",
            name: "WR",
            desc: '''
                  Initiates a programming sequence that writes the data in !!DIRECT_ACCESS_WDATA_0
                  and !!DIRECT_ACCESS_WDATA_1 (for 64bit partitions) to the location specified by
                  !!DIRECT_ACCESS_ADDRESS.
                  '''
          }
          { bits: "2",
            name: "DIGEST",
            desc: '''
                  Initiates the digest calculation and locking sequence for the partition specified by
                  !!DIRECT_ACCESS_ADDRESS.
                  '''
          }
        ]
      }
      { name: "DIRECT_ACCESS_ADDRESS",
        desc: "Address register for direct accesses.",
        swaccess: "rw",
        hwaccess: "hro",
        hwqe:     "false",
        regwen:   "DIRECT_ACCESS_REGWEN",
        tags: [ // The enable register "DIRECT_ACCESS_REGWEN" is HW controlled,
                // so not able to predict this register value automatically
                "excl:CsrNonInitTests:CsrExclCheck"],
        fields: [
          { bits: "OtpByteAddrWidth-1:0",
            desc: '''
                  This is the address for the OTP word to be read or written through
                  the direct access interface. Note that the address is aligned to the access size
                  internally, hence bits 1:0 are ignored for 32bit accesses, and bits 2:0 are ignored
                  for 64bit accesses.

                  For the digest calculation command, set this register to the partition base offset.
                  '''
          }
        ]
      }
      { multireg: {
          name:     "DIRECT_ACCESS_WDATA",
          desc:     '''Write data for direct accesses.
                    Hardware automatically determines the access granule (32bit or 64bit) based on which
                    partition is being written to.
                    ''',
          count:    "NumDaiWords", // 2 x 32bit = 64bit
          swaccess: "rw",
          hwaccess: "hro",
          hwqe:     "false",
          regwen:   "DIRECT_ACCESS_REGWEN",
          cname:    "WORD",
          tags: [ // The value of this register is written from "DIRECT_ACCESS_RDATA",
                  // so could not predict this register value automatically
                  "excl:CsrAllTests:CsrExclCheck"],
          fields: [
            { bits: "31:0"
            }
          ]
        }
      },
      { multireg: {
          name:     "DIRECT_ACCESS_RDATA",
          desc:     '''Read data for direct accesses.
                    Hardware automatically determines the access granule (32bit or 64bit) based on which
                    partition is read from.
                    ''',
          count:    "NumDaiWords", // 2 x 32bit = 64bit
          swaccess: "ro",
          hwaccess: "hwo",
          hwext:    "true",
          cname:    "WORD",
          fields: [
            { bits: "31:0"
            }
          ]
        }
      },

      //////////////////////////////////////
      // Integrity and Consistency Checks //
      //////////////////////////////////////
      { name: "CHECK_TRIGGER_REGWEN",
        desc: '''
              Register write enable for !!CHECK_TRIGGER.
              ''',
        swaccess: "rw0c",
        hwaccess: "none",
        fields: [
          { bits:   "0",
            desc: '''
            When cleared to 0, the !!CHECK_TRIGGER register cannot be written anymore.
            Write 0 to clear this bit.
            '''
            resval: 1,
          },
        ]
      },
      { name: "CHECK_TRIGGER",
        desc: "Command register for direct accesses.",
        swaccess: "r0w1c",
        hwaccess: "hro",
        hwqe:     "true",
        hwext:    "true",
        regwen:   "CHECK_TRIGGER_REGWEN",
        fields: [
          { bits: "0",
            name: "INTEGRITY",
            desc: '''
            Writing 1 to this bit triggers an integrity check. SW should monitor !!STATUS.CHECK_PENDING
            and wait until the check has been completed. If there are any errors, those will be flagged
            in the !!STATUS and !!ERR_CODE registers, and via the interrupts and alerts.
            '''
          }
          { bits: "1",
            name: "CONSISTENCY",
            desc: '''
            Writing 1 to this bit triggers a consistency check. SW should monitor !!STATUS.CHECK_PENDING
            and wait until the check has been completed. If there are any errors, those will be flagged
            in the !!STATUS and !!ERR_CODE registers, and via interrupts and alerts.
            '''
          }
        ]
      },
      { name: "CHECK_REGWEN",
        desc: '''
              Register write enable for !!INTEGRITY_CHECK_PERIOD and !!CONSISTENCY_CHECK_PERIOD.
              ''',
        swaccess: "rw0c",
        hwaccess: "none",
        fields: [
          { bits:   "0",
            desc: '''
            When cleared to 0, !!INTEGRITY_CHECK_PERIOD and !!CONSISTENCY_CHECK_PERIOD registers cannot be written anymore.
            Write 0 to clear this bit.
            '''
            resval: 1,
          },
        ]
      },
      { name: "CHECK_TIMEOUT",
        desc: '''
              Timeout value for the integrity and consistency checks.
              ''',
        swaccess: "rw",
        hwaccess: "hro",
        regwen:   "CHECK_REGWEN",
        tags: [ // Do not write to this automatically, as it may trigger fatal alert, and cause
                // escalation. TODO: check with designer if the trigger escalation part is intended.
                "excl:CsrAllTests:CsrExclWrite"],
        fields: [
          { bits: "31:0",
            desc: '''
            Timeout value in cycles for the for the integrity and consistency checks. If an integrity or consistency
            check does not complete within the timeout window, an error will be flagged in the !!STATUS register,
            an otp_error interrupt will be raised, and an fatal_check_error alert will be sent out. The timeout should
            be set to a large value to stay on the safe side. The maximum check time can be upper bounded by the
            number of cycles it takes to readout, scramble and digest the entire OTP array. Since this amounts to
            roughly 25k cycles, it is recommended to set this value to at least 100'000 cycles in order to stay on the
            safe side. A value of zero disables the timeout mechanism (default).
            '''
            resval: 0,
          },
        ]
      },
      { name: "INTEGRITY_CHECK_PERIOD",
        desc: '''
              This value specifies the maximum period that can be generated pseudo-randomly.
              Only applies to the HW_CFG and SECRET* partitions, once they are locked.
              '''
        swaccess: "rw",
        hwaccess: "hro",
        regwen:   "CHECK_REGWEN",
        fields: [
          { bits: "31:0",
            desc: '''
            The pseudo-random period is generated using a 40bit LFSR internally, and this register defines
            the bit mask to be applied to the LFSR output in order to limit its range. The value of this
            register is left shifted by 8bits and the lower bits are set to 8'hFF in order to form the 40bit mask.
            A recommended value is 0x3_FFFF, corresponding to a maximum period of ~2.8s at 24MHz.
            A value of zero disables the timer (default). Note that a one-off check can always be triggered via
            !!CHECK_TRIGGER.INTEGRITY.
            '''
            resval: "0"
          }
        ]
      }
      { name: "CONSISTENCY_CHECK_PERIOD",
        desc: '''
              This value specifies the maximum period that can be generated pseudo-randomly.
              This applies to the LIFE_CYCLE partition and the HW_CFG and SECRET* partitions, once they are locked.
              '''
        swaccess: "rw",
        hwaccess: "hro",
        regwen:   "CHECK_REGWEN",
        fields: [
          { bits: "31:0",
            desc: '''
            The pseudo-random period is generated using a 40bit LFSR internally, and this register defines
            the bit mask to be applied to the LFSR output in order to limit its range. The value of this
            register is left shifted by 8bits and the lower bits are set to 8'hFF in order to form the 40bit mask.
            A recommended value is 0x3FF_FFFF, corresponding to a maximum period of ~716s at 24MHz.
            A value of zero disables the timer (default). Note that a one-off check can always be triggered via
            !!CHECK_TRIGGER.CONSISTENCY.
            '''
            resval: "0"
          }
        ]
      }

      ////////////////////////////////////
      // Dynamic Locks of SW Parititons //
      ////////////////////////////////////
  % for part in otp_mmap.config["partitions"]:
    % if part["read_lock"].lower() == "csr":
      { name: "${part["name"]}_READ_LOCK",
        desc: '''
              Runtime read lock for the ${part["name"]} partition.
              ''',
        swaccess: "rw0c",
        hwaccess: "hro",
        regwen:   "DIRECT_ACCESS_REGWEN",
        tags:     [ // The enable register "DIRECT_ACCESS_REGWEN" is HW controlled,
                    // so not able to predict this register value automatically
                    "excl:CsrNonInitTests:CsrExclCheck"],
        fields: [
          { bits:   "0",
            desc: '''
            When cleared to 0, read access to the ${part["name"]} partition is locked.
            Write 0 to clear this bit.
            '''
            resval: 1,
          },
        ]
      },
    % endif
  % endfor

      ///////////////////////
      // Integrity Digests //
      ///////////////////////
  % for part in otp_mmap.config["partitions"]:
    % if part["sw_digest"]:
      { multireg: {
          name:     "${part["name"]}_DIGEST",
          desc:     '''
                    Integrity digest for the ${part["name"]} partition.
                    The integrity digest is 0 by default. Software must write this
                    digest value via the direct access interface in order to lock the partition.
                    After a reset, write access to the ${part["name"]} partition is locked and
                    the digest becomes visible in this CSR.
                    ''',
          count:     "NumDigestWords",
          swaccess:  "ro",
          hwaccess:  "hwo",
          hwext:     "true",
          cname:     "WORD",
          tags: [ // OTP internal HW will update status so can not auto-predict its value.
                  "excl:CsrAllTests:CsrExclCheck"],
          fields: [
            { bits: "31:0"
            }
          ]
        }
      },
    % elif part["hw_digest"]:
      { multireg: {
          name:     "${part["name"]}_DIGEST",
          desc:     '''
                    Integrity digest for the ${part["name"]} partition.
                    The integrity digest is 0 by default. The digest calculation can be triggered via the !!DIRECT_ACCESS_CMD.
                    After a reset, the digest then becomes visible in this CSR, and the corresponding partition becomes write-locked.
                    ''',
          count:     "NumDigestWords",
          swaccess:  "ro",
          hwaccess:  "hwo",
          hwext:     "true",
          cname:     "WORD",
          tags: [ // OTP internal HW will update status so can not auto-predict its value.
                  "excl:CsrAllTests:CsrExclCheck"],
          fields: [
            { bits: "31:0"
            }
          ]
        }
      },
    % endif
  % endfor

      ////////////////////////////////
      // Software Config Partitions //
      ////////////////////////////////
      { skipto: "0x1000" }

      { window: {
          name: "SW_CFG_WINDOW"
          items: "NumSwCfgWindowWords"
          swaccess: "ro",
          desc: '''
          Any read to this window directly maps to the corresponding offset in the creator and owner software
          config partitions, and triggers an OTP readout of the bytes requested. Note that the transaction
          will block until OTP readout has completed.
          '''
        }
      }
    ],

    // these CSRs are defined in a separate hjson specific to the closed source OTP wrapper.
    prim: [
    ]
  }
}
