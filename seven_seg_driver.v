`timescale 1ns / 1ps

module display(
    input wire [3:0] digit,
    output wire [6:0] seg
);
    reg [6:0] display_reg;

    always @* begin
        case(digit)
            0: display_reg = 7'b1000000;
            1: display_reg = 7'b1111001;
            2: display_reg = 7'b0100100;
            3: display_reg = 7'b0110000;
            4: display_reg = 7'b0011001;
            5: display_reg = 7'b0010010;
            6: display_reg = 7'b0000010;
            7: display_reg = 7'b1111000;
            8: display_reg = 7'b0000000;
            9: display_reg = 7'b0010000;
            default: display_reg = 7'b1111111;
        endcase 
    end
    assign seg = display_reg;

endmodule

module multi_digit_display(
    input clk,               // System clock (e.g., 50 MHz)
    input rst,               // Reset
    input wire [13:0] value,      // Integer input (0-9999)
    input wire enable_blink,      // Enable blinking
    output wire [6:0] seg,   // Segment output (active low)
    output reg [3:0] an      // Anode control (active low)
);
    reg [3:0] digit0, digit1, digit2, digit3;
    reg [1:0] anode_sel = 0;
    reg blink_state = 1;
    reg [25:0] blink_counter = 0;
    reg [15:0] refresh_counter = 0;
    reg [3:0] current_digit;

    // Split the value into digits
    always @* begin
        digit0 = value % 10;            
        digit1 = (value / 10) % 10;     
        digit2 = (value / 100) % 10;    
        digit3 = (value / 1000);        
    end

    // Blink logic: toggle every ~1 second
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            blink_counter <= 0;
            blink_state <= 1;
        end else if (enable_blink) begin
            blink_counter <= blink_counter + 1;
            if (blink_counter == 49_999_999) begin
                blink_counter <= 0;
                blink_state <= ~blink_state;
            end
        end else begin
            blink_state <= 1; // Always on if blinking not enabled
        end
    end

    // Slow down the refresh rate
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh_counter <= 0;
            anode_sel <= 0;
        end else begin
            refresh_counter <= refresh_counter + 1;
            if (refresh_counter == 50_000) begin
                refresh_counter <= 0;
                anode_sel <= anode_sel + 1;
            end
        end
    end

    always @* begin
        case (anode_sel)
            2'b00: begin
                an = 4'b1110; // Activate digit0 (LS digit)
                current_digit = digit0;
            end
            2'b01: begin
                an = 4'b1101; // Activate digit1
                current_digit = digit1;
            end
            2'b10: begin
                an = 4'b1011; // Activate digit2
                current_digit = digit2;
            end
            2'b11: begin
                an = 4'b0111; // Activate digit3 (MS digit)
                current_digit = digit3;
            end
        endcase
    end

    wire [6:0] raw_seg;
    display digit_to_seg(
        .digit(current_digit),
        .seg(raw_seg)
    );

    // Apply blink: if blink_state=0 and enable_blink=1, turn all segments off
    assign seg = (enable_blink && !blink_state) ? 7'b1111111 : raw_seg;

endmodule