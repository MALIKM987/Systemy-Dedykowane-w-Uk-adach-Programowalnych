`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Interfejs zgodny z treścią zadania:
//   BTN[3:0] - 4 przyciski monostabilne z debouncerem, zapis konfiguracji
//              do odpowiedniego kanału
//   SW[5:0]  - 6 przełączników bistabilnych:
//              SW[3:0] = duty 0..9  -> 0%..90% co 10%
//              SW[4]   = 0 edge-aligned, 1 center-aligned
//              SW[5]   = 0 high-true,    1 low-true
//   PWM_OUT[3:0] - 4 wyjścia PWM
//
// Wszystkie 4 kanały korzystają z jednego wspólnego licznika PWM.
//------------------------------------------------------------------------------
module pwm_driver_top #(
    parameter integer CLK_FREQ_HZ      = 100_000_000,
    parameter integer PWM_FREQ_HZ      = 50,
    parameter integer DEBOUNCE_CYCLES  = 1_000_000
)(
    input  wire       CLK,
    input  wire [5:0] SW,
    input  wire [3:0] BTN,
    output wire [3:0] PWM_OUT
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    localparam integer PERIOD_TICKS = CLK_FREQ_HZ / PWM_FREQ_HZ;
    localparam integer CNT_W        = clog2(PERIOD_TICKS);

    wire [CNT_W-1:0] pwm_cnt;
    wire [3:0]       btn_pulse;

    wire [15:0] duty_cfg;
    wire [3:0]  align_cfg;
    wire [3:0]  pol_cfg;

    genvar i;

    pwm_timebase #(
        .PERIOD_TICKS(PERIOD_TICKS),
        .CNT_W(CNT_W)
    ) u_pwm_timebase (
        .clk(CLK),
        .rst(1'b0),
        .pwm_cnt(pwm_cnt)
    );

    generate
        for (i = 0; i < 4; i = i + 1) begin : GEN_BTN_IF
            button_if #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
            ) u_button_if (
                .clk(CLK),
                .rst(1'b0),
                .raw_btn(BTN[i]),
                .btn_pulse(btn_pulse[i])
            );
        end
    endgenerate

    generate
        for (i = 0; i < 4; i = i + 1) begin : GEN_CHANNELS
            channel_cfg_reg u_channel_cfg_reg (
                .clk(CLK),
                .rst(1'b0),
                .load(btn_pulse[i]),
                .duty_step_in(SW[3:0]),
                .align_in(SW[4]),
                .polarity_in(SW[5]),
                .duty_step(duty_cfg[4*i+3 : 4*i]),
                .align_mode(align_cfg[i]),
                .polarity(pol_cfg[i])
            );

            pwm_channel #(
                .PERIOD_TICKS(PERIOD_TICKS),
                .CNT_W(CNT_W)
            ) u_pwm_channel (
                .pwm_cnt(pwm_cnt),
                .duty_step(duty_cfg[4*i+3 : 4*i]),
                .align_mode(align_cfg[i]),
                .polarity(pol_cfg[i]),
                .pwm_out(PWM_OUT[i])
            );
        end
    endgenerate

endmodule

//------------------------------------------------------------------------------
// Interfejs przycisku: synchronizer + debouncer + generator impulsu 1-taktowego
//------------------------------------------------------------------------------
module button_if #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire raw_btn,
    output wire btn_pulse
);
    wire btn_sync;
    wire btn_clean;

    sync_2ff u_sync_2ff (
        .clk(clk),
        .rst(rst),
        .din(raw_btn),
        .dout(btn_sync)
    );

    debounce #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_debounce (
        .clk(clk),
        .rst(rst),
        .noisy(btn_sync),
        .clean(btn_clean)
    );

    edge_to_pulse u_edge_to_pulse (
        .clk(clk),
        .rst(rst),
        .sig_in(btn_clean),
        .pulse(btn_pulse)
    );

endmodule

//------------------------------------------------------------------------------
// Synchronizator 2FF dla wejść asynchronicznych
//------------------------------------------------------------------------------
module sync_2ff (
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg  dout
);
    reg sync1;

    initial begin
        sync1 = 1'b0;
        dout  = 1'b0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync1 <= 1'b0;
            dout  <= 1'b0;
        end else begin
            sync1 <= din;
            dout  <= sync1;
        end
    end
endmodule

//------------------------------------------------------------------------------
// Debouncer przycisku
//------------------------------------------------------------------------------
module debounce #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire noisy,
    output reg  clean
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    localparam integer CNT_W = clog2(DEBOUNCE_CYCLES + 1);

    reg [CNT_W-1:0] cnt;

    initial begin
        clean = 1'b0;
        cnt   = {CNT_W{1'b0}};
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clean <= 1'b0;
            cnt   <= {CNT_W{1'b0}};
        end else begin
            if (noisy == clean) begin
                cnt <= {CNT_W{1'b0}};
            end else begin
                if (cnt == DEBOUNCE_CYCLES - 1) begin
                    clean <= noisy;
                    cnt   <= {CNT_W{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end
endmodule

//------------------------------------------------------------------------------
// Zamiana zbocza narastającego na impuls 1-taktowy
//------------------------------------------------------------------------------
module edge_to_pulse (
    input  wire clk,
    input  wire rst,
    input  wire sig_in,
    output reg  pulse
);
    reg sig_d;

    initial begin
        sig_d = 1'b0;
        pulse = 1'b0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sig_d <= 1'b0;
            pulse <= 1'b0;
        end else begin
            pulse <= sig_in & ~sig_d;
            sig_d <= sig_in;
        end
    end
endmodule

//------------------------------------------------------------------------------
// Rejestr konfiguracji pojedynczego kanału
//------------------------------------------------------------------------------
module channel_cfg_reg (
    input  wire       clk,
    input  wire       rst,
    input  wire       load,
    input  wire [3:0] duty_step_in,
    input  wire       align_in,
    input  wire       polarity_in,
    output reg  [3:0] duty_step,
    output reg        align_mode,
    output reg        polarity
);

    wire [3:0] duty_sat;
    assign duty_sat = (duty_step_in > 4'd9) ? 4'd9 : duty_step_in;

    initial begin
        duty_step  = 4'd0;
        align_mode = 1'b0;
        polarity   = 1'b0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            duty_step  <= 4'd0;
            align_mode <= 1'b0;
            polarity   <= 1'b0;
        end else if (load) begin
            duty_step  <= duty_sat;
            align_mode <= align_in;
            polarity   <= polarity_in;
        end
    end
endmodule

//------------------------------------------------------------------------------
// Wspólny licznik czasu PWM dla wszystkich kanałów
//------------------------------------------------------------------------------
module pwm_timebase #(
    parameter integer PERIOD_TICKS = 2_000_000,
    parameter integer CNT_W        = 21
)(
    input  wire            clk,
    input  wire            rst,
    output reg [CNT_W-1:0] pwm_cnt
);

    initial begin
        pwm_cnt = {CNT_W{1'b0}};
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_cnt <= {CNT_W{1'b0}};
        end else begin
            if (pwm_cnt == PERIOD_TICKS - 1)
                pwm_cnt <= {CNT_W{1'b0}};
            else
                pwm_cnt <= pwm_cnt + 1'b1;
        end
    end
endmodule

//------------------------------------------------------------------------------
// Generator pojedynczego kanału PWM
//------------------------------------------------------------------------------
module pwm_channel #(
    parameter integer PERIOD_TICKS = 2_000_000,
    parameter integer CNT_W        = 21
)(
    input  wire [CNT_W-1:0] pwm_cnt,
    input  wire [3:0]       duty_step,
    input  wire             align_mode,
    input  wire             polarity,
    output wire             pwm_out
);

    reg [CNT_W-1:0] duty_ticks;
    reg [CNT_W-1:0] start_tick;
    reg [CNT_W-1:0] end_tick;
    reg             active_region;

    always @(*) begin
        case (duty_step)
            4'd0: duty_ticks = 0;
            4'd1: duty_ticks = (PERIOD_TICKS * 1) / 10;
            4'd2: duty_ticks = (PERIOD_TICKS * 2) / 10;
            4'd3: duty_ticks = (PERIOD_TICKS * 3) / 10;
            4'd4: duty_ticks = (PERIOD_TICKS * 4) / 10;
            4'd5: duty_ticks = (PERIOD_TICKS * 5) / 10;
            4'd6: duty_ticks = (PERIOD_TICKS * 6) / 10;
            4'd7: duty_ticks = (PERIOD_TICKS * 7) / 10;
            4'd8: duty_ticks = (PERIOD_TICKS * 8) / 10;
            default: duty_ticks = (PERIOD_TICKS * 9) / 10;
        endcase

        start_tick = (PERIOD_TICKS - duty_ticks) / 2;
        end_tick   = start_tick + duty_ticks;

        if (align_mode == 1'b0)
            active_region = (pwm_cnt < duty_ticks);
        else
            active_region = (pwm_cnt >= start_tick) && (pwm_cnt < end_tick);
    end

    assign pwm_out = (polarity == 1'b0) ? active_region : ~active_region;

endmodule