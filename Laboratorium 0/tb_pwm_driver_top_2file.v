`timescale 1us / 1ns

module tb_pwm_driver_top;

    localparam integer CLK_FREQ_HZ     = 100_000;
    localparam integer PWM_FREQ_HZ     = 50;
    localparam integer DEBOUNCE_CYCLES = 8;
    localparam integer PERIOD_TICKS    = CLK_FREQ_HZ / PWM_FREQ_HZ;

    reg        CLK;
    reg  [5:0] SW;
    reg  [3:0] BTN;
    wire [3:0] PWM_OUT;

    integer duty;

    reg [15:0] prev_duty_cfg;
    reg [3:0]  prev_align_cfg;
    reg [3:0]  prev_pol_cfg;
    reg [3:0]  prev_pwm_out;

    pwm_driver_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .PWM_FREQ_HZ(PWM_FREQ_HZ),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) dut (
        .CLK(CLK),
        .SW(SW),
        .BTN(BTN),
        .PWM_OUT(PWM_OUT)
    );

    //--------------------------------------------------------------------------
    // Zegar
    //--------------------------------------------------------------------------
    initial CLK = 1'b0;
    always #5 CLK = ~CLK;   // 100 kHz -> 10 us period

    //--------------------------------------------------------------------------
    // Task: ustawienie przełączników
    //--------------------------------------------------------------------------
    task set_switches;
        input [3:0] duty_val;
        input       align;
        input       pol;
        begin
            SW[3:0] = duty_val;
            SW[4]   = align;
            SW[5]   = pol;

            $display("[%0t us] SW <= duty=%0d0%% align=%s pol=%s",
                     $time,
                     duty_val,
                     (align ? "CENTER" : "EDGE"),
                     (pol   ? "LOW-TRUE" : "HIGH-TRUE"));

            repeat (2) @(posedge CLK);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: dłuższe "brudne" naciśnięcie przycisku
    //--------------------------------------------------------------------------
    task press_button_bouncy;
        input integer idx;
        begin
            $display("[%0t us] BTN[%0d] bounce start", $time, idx);

            BTN[idx] = 1'b1; @(posedge CLK);
            BTN[idx] = 1'b0; @(posedge CLK);
            BTN[idx] = 1'b1; @(posedge CLK);
            BTN[idx] = 1'b0; @(posedge CLK);

            BTN[idx] = 1'b1;
            // dużo większy zapas niż poprzednio
            repeat (DEBOUNCE_CYCLES + 12) @(posedge CLK);

            BTN[idx] = 1'b0;
            repeat (DEBOUNCE_CYCLES + 12) @(posedge CLK);

            $display("[%0t us] BTN[%0d] released", $time, idx);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: zaprogramowanie kanału
    //--------------------------------------------------------------------------
    task program_channel;
        input integer ch;
        input [3:0] duty_val;
        input       align;
        input       pol;
        begin
            $display("------------------------------------------------------------");
            $display("[%0t us] PROGRAM CH%0d : duty=%0d0%% align=%s pol=%s",
                     $time, ch, duty_val,
                     (align ? "CENTER" : "EDGE"),
                     (pol   ? "LOW-TRUE" : "HIGH-TRUE"));

            set_switches(duty_val, align, pol);
            press_button_bouncy(ch);
        end
    endtask

    //--------------------------------------------------------------------------
    // Czekanie N pełnych okresów PWM
    //--------------------------------------------------------------------------
    task wait_pwm_periods;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                repeat (PERIOD_TICKS) @(posedge CLK);
        end
    endtask

    //--------------------------------------------------------------------------
    // Logowanie ważnych zdarzeń
    //--------------------------------------------------------------------------

    initial begin
        prev_duty_cfg  = 16'hxxxx;
        prev_align_cfg = 4'hx;
        prev_pol_cfg   = 4'hx;
        prev_pwm_out   = 4'hx;
    end

    // Log: wykryte impulsy po debouncerze
    always @(posedge CLK) begin
        if (dut.btn_pulse != 4'b0000) begin
            $display("[%0t us] btn_pulse=%b", $time, dut.btn_pulse);
        end
    end

    // Log: zmiana konfiguracji kanałów
    always @(posedge CLK) begin
        if (dut.duty_cfg !== prev_duty_cfg ||
            dut.align_cfg !== prev_align_cfg ||
            dut.pol_cfg !== prev_pol_cfg) begin

            $display("[%0t us] CFG changed:", $time);
            $display("           CH0 duty=%0d align=%0d pol=%0d",
                     dut.duty_cfg[3:0],   dut.align_cfg[0], dut.pol_cfg[0]);
            $display("           CH1 duty=%0d align=%0d pol=%0d",
                     dut.duty_cfg[7:4],   dut.align_cfg[1], dut.pol_cfg[1]);
            $display("           CH2 duty=%0d align=%0d pol=%0d",
                     dut.duty_cfg[11:8],  dut.align_cfg[2], dut.pol_cfg[2]);
            $display("           CH3 duty=%0d align=%0d pol=%0d",
                     dut.duty_cfg[15:12], dut.align_cfg[3], dut.pol_cfg[3]);

            prev_duty_cfg  <= dut.duty_cfg;
            prev_align_cfg <= dut.align_cfg;
            prev_pol_cfg   <= dut.pol_cfg;
        end
    end

    // Log: zmiana wyjść PWM
    always @(posedge CLK) begin
        if (PWM_OUT !== prev_pwm_out) begin
            $display("[%0t us] PWM_OUT=%b", $time, PWM_OUT);
            prev_pwm_out <= PWM_OUT;
        end
    end

    //--------------------------------------------------------------------------
    // Główna sekwencja
    //--------------------------------------------------------------------------
    initial begin
        BTN = 4'b0000;
        SW  = 6'b000000;

        $display("============================================================");
        $display("START SYMULACJI");
        $display("CLK_FREQ_HZ=%0d, PWM_FREQ_HZ=%0d, PERIOD_TICKS=%0d",
                 CLK_FREQ_HZ, PWM_FREQ_HZ, PERIOD_TICKS);
        $display("============================================================");

        repeat (10) @(posedge CLK);

        // Etap 1 - kanały po kolei
        $display("");
        $display("=== ETAP 1: Programowanie kanałów po kolei ===");
        program_channel(0, 4'd1, 1'b0, 1'b0);   // 10% edge high
        wait_pwm_periods(2);

        program_channel(1, 4'd3, 1'b0, 1'b0);   // 30% edge high
        wait_pwm_periods(2);

        program_channel(2, 4'd5, 1'b1, 1'b0);   // 50% center high
        wait_pwm_periods(2);

        program_channel(3, 4'd7, 1'b1, 1'b1);   // 70% center low
        wait_pwm_periods(3);

        // Etap 2 - wszystkie duty na CH0
        $display("");
        $display("=== ETAP 2: CH0 wszystkie duty, EDGE, HIGH ===");
        for (duty = 0; duty <= 9; duty = duty + 1) begin
            program_channel(0, duty[3:0], 1'b0, 1'b0);
            wait_pwm_periods(2);
        end

        // Etap 3 - wszystkie duty na CH1
        $display("");
        $display("=== ETAP 3: CH1 wszystkie duty, CENTER, HIGH ===");
        for (duty = 0; duty <= 9; duty = duty + 1) begin
            program_channel(1, duty[3:0], 1'b1, 1'b0);
            wait_pwm_periods(2);
        end

        // Etap 4 - wszystkie duty na CH2
        $display("");
        $display("=== ETAP 4: CH2 wszystkie duty, EDGE, LOW ===");
        for (duty = 0; duty <= 9; duty = duty + 1) begin
            program_channel(2, duty[3:0], 1'b0, 1'b1);
            wait_pwm_periods(2);
        end

        // Etap 5 - wszystkie duty na CH3
        $display("");
        $display("=== ETAP 5: CH3 wszystkie duty, CENTER, LOW ===");
        for (duty = 0; duty <= 9; duty = duty + 1) begin
            program_channel(3, duty[3:0], 1'b1, 1'b1);
            wait_pwm_periods(2);
        end

        // Etap 6 - końcowe porównanie
        $display("");
        $display("=== ETAP 6: Koncowe porownanie wszystkich kanałów ===");

        program_channel(0, 4'd2, 1'b0, 1'b0);   // 20% edge high
        wait_pwm_periods(1);

        program_channel(1, 4'd4, 1'b1, 1'b0);   // 40% center high
        wait_pwm_periods(1);

        program_channel(2, 4'd6, 1'b0, 1'b1);   // 60% edge low
        wait_pwm_periods(1);

        program_channel(3, 4'd8, 1'b1, 1'b1);   // 80% center low
        wait_pwm_periods(5);

        $display("");
        $display("============================================================");
        $display("KONIEC SYMULACJI");
        $display("============================================================");

        $finish;
    end

endmodule
