module nexys_core(
    input  wire        clk,
    input  wire        cpu_resetn,
    input  wire [15:0] sw,
    output wire [15:0] led
);
    // reset: powers up in reset, released 3 clocks after CPU_RESETN is high
    reg [2:0] rs;
    always @(posedge clk) rs <= {rs[1:0], cpu_resetn};
    wire rst_n = rs[2];

    // run-time configuration from the switches
    wire        gen_en = sw[0];
    wire [2:0]  pat    = sw[3:1];
    wire [15:0] rate   = {2'b00, sw[7:4], 10'd0};      // 0.0625 flit/cycle/node per step
    reg  [7:0]  rthr;
    always @(*) case (sw[9:8])
        2'd0:    rthr = 8'hFF;                          // sinks always ready
        2'd1:    rthr = 8'hC0;                          // 75 % ready
        2'd2:    rthr = 8'h80;                          // 50 % ready
        default: rthr = 8'h40;                          // 25 % ready
    endcase

    wire [31:0] now;
    wire        inject_block_req;
    wire [15:0] inj_valid, inj_ready, ej_valid, ej_ready;
    wire [255:0] inj_data, ej_data;
    wire [31:0]  inj_type, ej_type;
    wire [15:0] ib_ack, src_empty, pkt_done, sink_err, drop_any;
    wire [255:0] lat_t, lat_n;

    genvar n;
    generate
        for (n = 0; n < 16; n = n + 1) begin : g_node
            wire [31:0] dr;
            traffic_generator #(.NODE(n), .SEED(32'h1)) u_tg (
                .clk(clk), .rst_n(rst_n), .now(now),
                .gen_enable(gen_en), .rate(rate), .pattern(pat),
                .hot_node(4'd5), .hot_pct(8'd128), .max_packets(32'd0),
                .inj_data(inj_data[16*n +: 16]), .inj_type(inj_type[2*n +: 2]),
                .inj_valid(inj_valid[n]), .inj_ready(inj_ready[n]),
                .inject_block_req(inject_block_req), .inject_block_ack(ib_ack[n]),
                .src_empty(src_empty[n]),
                .create_pulse(), .create_dst(), .create_seq(), .flit_accept(),
                .created(), .dropped(dr), .injected(), .q_count());
            assign drop_any[n] = |dr;

            packet_sink #(.NODE(n), .SEED(32'h1)) u_sk (
                .clk(clk), .rst_n(rst_n), .now(now), .ready_thresh(rthr),
                .ej_data(ej_data[16*n +: 16]), .ej_type(ej_type[2*n +: 2]),
                .ej_valid(ej_valid[n]), .ej_ready(ej_ready[n]),
                .pkt_done(pkt_done[n]), .pkt_src(), .pkt_pid(),
                .pkt_lat_total(lat_t[16*n +: 16]), .pkt_lat_net(lat_n[16*n +: 16]),
                .pkts_ok(), .flits(), .err_dest_cnt(), .err_order_cnt(), .err_integ_cnt(),
                .err_any(sink_err[n]));
        end
    endgenerate

    wire        active_mode, req_mode, transition_busy, drain_timeout, network_drained;
    wire [2:0]  ctrl_state;
    wire [7:0]  gcong, graw;
    wire        proto_err, alloc_err;

    noc_top u_noc (
        .clk(clk), .rst_n(rst_n),
        .inj_data(inj_data), .inj_type(inj_type), .inj_valid(inj_valid), .inj_ready(inj_ready),
        .ej_data(ej_data), .ej_type(ej_type), .ej_valid(ej_valid), .ej_ready(ej_ready),
        .inject_block_req(inject_block_req), .inject_block_ack(ib_ack), .src_empty(src_empty),
        .active_mode(active_mode), .req_mode(req_mode),
        .global_congestion(gcong), .global_raw(graw),
        .transition_busy(transition_busy), .drain_timeout(drain_timeout),
        .network_drained(network_drained), .ctrl_state(ctrl_state),
        .router_empty(), .fifo_occ_all(), .ewma_all(),
        .proto_err_any(proto_err), .alloc_err_any(alloc_err),
        .cycle_cnt(), .tr_blocked(), .tr_ackwait(), .tr_drain(),
        .tot_blocked(), .tot_ackwait(), .tot_drain(), .transitions(),
        .t_block(), .t_ack(), .t_drained(), .t_switch(), .t_resume());

    wire        meas_en, meas_done, stall_flag;
    wire [31:0] sw_total, w_switches, w_pp1, w_blocked, drain_max, pkts_total, stall_max;
    wire [15:0] lat_max;

    performance_monitor u_pm (
        .clk(clk), .rst_n(rst_n), .warmup(32'd10000), .measure(32'd12500000),
        .active_mode(active_mode), .req_mode(req_mode), .inject_block_req(inject_block_req),
        .inj_xfer(inj_valid & inj_ready), .ej_xfer(ej_valid & ej_ready),
        .pkt_done(pkt_done), .lat_total(lat_t), .lat_net(lat_n),
        .now(now), .meas_en(meas_en), .meas_done(meas_done), .meas_cycles(),
        .sw_total(sw_total), .w_switches(w_switches), .w_to_adapt(), .w_to_xy(),
        .w_req_toggles(), .w_blk_starts(), .w_pp0(), .w_pp1(w_pp1), .w_pp2(), .w_pp3(),
        .w_dwell_cnt(), .w_dwell_sum(), .w_dwell_min(), .w_dwell_max(), .w_adapt_cycles(),
        .w_blocked(w_blocked), .drain_cnt(), .drain_sum(), .drain_min(), .drain_max(drain_max),
        .blk_len_now(), .w_pkts(), .w_lat_total_sum(), .w_lat_total_sq(),
        .w_lat_total_max(lat_max), .w_lat_net_sum(), .w_lat_net_sq(), .w_lat_net_max(),
        .w_inj_flits(), .w_ej_flits(), .pkts_total(pkts_total), .inj_flits_total(),
        .ej_flits_total(), .inflight(), .stall_cnt(), .stall_max(stall_max),
        .stall_flag(stall_flag));

    // sticky error flags
    reg e_proto, e_alloc, e_drain, e_drop;
    always @(posedge clk)
        if (!rst_n) begin e_proto <= 1'b0; e_alloc <= 1'b0; e_drain <= 1'b0; e_drop <= 1'b0; end
        else begin
            e_proto <= e_proto | proto_err;
            e_alloc <= e_alloc | alloc_err;
            e_drain <= e_drain | drain_timeout;
            e_drop  <= e_drop  | (|drop_any);
        end

    // LED view selected by SW15:13
    reg [15:0] view;
    always @(*) case (sw[15:13])
        3'd0:    view = {meas_done, stall_flag, |sink_err, e_alloc, e_proto, e_drain, e_drop,
                         transition_busy, inject_block_req, req_mode, active_mode,
                         network_drained, meas_en, ctrl_state};
        3'd1:    view = sw_total[15:0];
        3'd2:    view = pkts_total[15:0];
        3'd3:    view = {w_pp1[7:0], w_switches[7:0]};
        3'd4:    view = {gcong, graw};
        3'd5:    view = lat_max;
        3'd6:    view = drain_max[15:0];
        default: view = stall_max[15:0];
    endcase
    assign led = view;

    wire unused = &{1'b0, w_blocked};
endmodule
