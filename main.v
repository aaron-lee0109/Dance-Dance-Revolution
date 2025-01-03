`timescale 1ns / 1ps

module rng(
    input clk,
    input rst,
    output reg [7:0] rand_num
    );

    reg [7:0] lfsr;
    wire feedback;

    assign feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= 8'h1;
        end
        else begin
            lfsr <= {lfsr[6:0], feedback};
        end
    end

    // Output the current LFSR state as the random number
    always @(posedge clk) begin
        rand_num <= lfsr;
    end

endmodule


module main(
    input clk,
    input rst,
    input btn_left,
    input btn_down,
    input btn_up,
    input btn_right,
    output hsync,
    output vsync,
    output [11:0] rgb,
    output wire [6:0] seg,
    output wire [3:0] an
    );
    
    // VGA controller signals
    wire video_on;
    wire [9:0] x, y;
    
    // Random Number Generator
    wire [7:0] rand_num;
    rng random_gen(
        .clk(clk),
        .rst(rst),
        .rand_num(rand_num)
    );
    
    // Parameters
    parameter NUM_COLUMNS = 4;
    parameter COLUMN_WIDTH = 160;
    parameter SCREEN_HEIGHT = 480;
    parameter BOX_SIZE = 20;
    parameter MAX_ARROWS_ON_SCREEN = 16; 
    parameter CATCH_ZONE_Y_START = 40;   
    parameter CATCH_ZONE_Y_END   = 60;
    
    // Color definitions
    wire [11:0] bg_color                 = 12'h000; // Black background
    wire [11:0] arrow_color              = 12'hF00; // Red arrows
    wire [11:0] catch_zone_color         = 12'hFF0; // Yellow catch zone
    wire [11:0] active_catch_zone_color  = 12'h0F0; // Green when arrow overlaps catch zone
    
    // Arrow data structures
    reg arrow_active [0:MAX_ARROWS_ON_SCREEN-1];       // Active arrows
    reg [1:0] arrow_col [0:MAX_ARROWS_ON_SCREEN-1];    // Column index (0 to 3)
    reg [9:0] arrow_y   [0:MAX_ARROWS_ON_SCREEN-1];    // Y position
    
    reg [13:0] score;
    reg [13:0] miss_counter;
    reg [13:0] display_digits;
    reg is_blink;

    // Debounced Button Signals
    wire btn_left_debounced;
    wire btn_down_debounced;
    wire btn_up_debounced;
    wire btn_right_debounced;
    
    vga_controller vga_c(
        .clk_100MHz(clk),
        .reset(rst),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .p_tick(p_tick),
        .x(x),
        .y(y)
    );

    debounce db_left (
        .clk(clk),
        .rst(rst),
        .button_in(btn_left),
        .button_out(btn_left_debounced)
    );
    debounce db_down (
        .clk(clk),
        .rst(rst),
        .button_in(btn_down),
        .button_out(btn_down_debounced)
    );
    debounce db_up (
        .clk(clk),
        .rst(rst),
        .button_in(btn_up),
        .button_out(btn_up_debounced)
    );
    debounce db_right (
        .clk(clk),
        .rst(rst),
        .button_in(btn_right),
        .button_out(btn_right_debounced)
    );
    multi_digit_display score_display (
        .clk(clk),
        .value(display_digits),
        .enable_blink(is_blink),
        .seg(seg),
        .an(an)
        );

    
    // Timing parameters
    parameter SPAWN_INTERVAL = 85000000; // Adjust as needed for game speed
    parameter MOVE_INTERVAL  = 900000;  // Adjust for arrow speed
    
    // Counters
    reg [31:0] spawn_counter;
    reg [31:0] move_counter;
    
    // Random Column Selection
    reg [1:0] rand_col;
    
    reg [4:0] i; 
    reg [4:0] j;
    reg [4:0] k;
    reg [4:0] n;
    
    // Registers for drawing logic
    reg [11:0] rgb_reg;
    reg arrow_in_catch_zone;
    integer found_slot;

    // Main game logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all game state
            spawn_counter   <= 0;
            move_counter    <= 0;
            score           <= 0;
            miss_counter    <= 0;
            display_digits  <= 0;
            is_blink        <= 0;
            for (i = 0; i < MAX_ARROWS_ON_SCREEN; i = i + 1) begin
                arrow_active[i] <= 0;
                arrow_col[i]    <= 0;
                arrow_y[i]      <= 0;
            end
        end
        // Here, change LED to show score.
        else if( miss_counter == 10 )begin 
            display_digits  <= score;
            is_blink <= 1;
        end
        // Here, show how many misses you have made on the LED
        else begin
            // Movement Logic
            display_digits  <= 10 - miss_counter;
            is_blink <= 0;

            if (move_counter >= MOVE_INTERVAL) begin
                move_counter <= 0;
                for (i = 0; i < MAX_ARROWS_ON_SCREEN; i = i + 1) begin
                    if (arrow_active[i]) begin
                        if (arrow_y[i] > 0) begin
                            arrow_y[i] <= arrow_y[i] - 1; // Move arrow up
                        end else begin
                            arrow_active[i] <= 0; // Deactivate arrow
                        end
                    end
                end
            end else begin
                move_counter <= move_counter + 1;
            end
            
            // Spawn Logic
            if (spawn_counter >= SPAWN_INTERVAL) begin
                spawn_counter <= 0;
                // Find a free slot for the new arrow
                found_slot = 0;
                rand_col <= rand_num[1:0]; // Use lower 2 bits for columns 0-3
                for (j = 0; j < MAX_ARROWS_ON_SCREEN && !found_slot; j = j + 1) begin
                    if (!arrow_active[j]) begin
                        // Spawn new arrow
                        arrow_active[j] <= 1;
                        arrow_col[j]    <= rand_col;
                        arrow_y[j]      <= SCREEN_HEIGHT - BOX_SIZE - 40;
                        found_slot = 1;
                    end
                end
            end else begin
                spawn_counter <= spawn_counter + 1;
            end
            
            // Catch Logic
            for (k = 0; k < MAX_ARROWS_ON_SCREEN; k = k + 1) begin
                if (arrow_active[k]) begin
                    // Check if arrow is within the catch zone
                    if (arrow_y[k] <= CATCH_ZONE_Y_END && arrow_y[k] >= CATCH_ZONE_Y_START) begin
                        // Check for button press corresponding to arrow's column
                        if ((arrow_col[k] == 2'b00 && btn_left_debounced) ||
                            (arrow_col[k] == 2'b01 && btn_down_debounced) ||
                            (arrow_col[k] == 2'b10 && btn_up_debounced) ||
                            (arrow_col[k] == 2'b11 && btn_right_debounced)) begin
                            // Successful catch
                            score <= score + 1;
                            arrow_active[k] <= 0; // Deactivate the arrow
                        end
                    end else if (arrow_y[k] < CATCH_ZONE_Y_START) begin
                        // Arrow has passed the catch zone without being caught
                        miss_counter <= miss_counter + 1;
                        arrow_active[k] <= 0; // Deactivate the arrow
                    end
                end
            end
        end
    end
    
    integer col_center;
    reg [9:0] tri_equation;
    
    // Drawing logic
    always @* begin
        if (video_on) begin
            // Default background color
            rgb_reg = bg_color;
            arrow_in_catch_zone = 0;
            
            // Draw all active arrows and check for overlap with catch zone
            for (n = 0; n < MAX_ARROWS_ON_SCREEN; n = n + 1) begin
                if (arrow_active[n]) begin
                    col_center = (arrow_col[n] * COLUMN_WIDTH) + (COLUMN_WIDTH / 2);
                    if(arrow_col[n] == 0) begin
                        tri_equation = x - 70 - (COLUMN_WIDTH * arrow_col[n] );
                        tri_equation = tri_equation >> 1;
                        if (x >= col_center - (BOX_SIZE / 2) &&
                            x <  col_center + (BOX_SIZE / 2) &&
                            y >= -tri_equation + arrow_y[n] + 10 &&
                            y <= tri_equation + arrow_y[n] + 10) begin
                            if (y >= CATCH_ZONE_Y_START && y <= CATCH_ZONE_Y_END) begin
                                // Arrow is in catch zone
                                rgb_reg = active_catch_zone_color; // Green
                                arrow_in_catch_zone = 1;
                            end 
                            else begin
                                // Arrow outside catch zone
                                rgb_reg = arrow_color; // Red arrow
                            end
                        end
                   end
                   
                   // wait!
                   else if (arrow_col[n] == 3) begin
                        tri_equation = 90 +(COLUMN_WIDTH * arrow_col[n] ) - x;
                        tri_equation = tri_equation >> 1;
                        if (x >= col_center - (BOX_SIZE / 2) &&
                            x <  col_center + (BOX_SIZE / 2) &&
                            y >= -tri_equation + arrow_y[n] + 10 &&
                            y <= tri_equation + arrow_y[n] + 10) begin
                            if (y >= CATCH_ZONE_Y_START && y <= CATCH_ZONE_Y_END) begin
                                // Arrow is in catch zone
                                rgb_reg = active_catch_zone_color; // Green
                                arrow_in_catch_zone = 1;
                            end 
                            else begin
                                // Arrow outside catch zone
                                rgb_reg = arrow_color; // Red arrow
                            end
                        end
                   end
                   else if (arrow_col[n] == 2) begin
                       tri_equation = y - arrow_y[n];
                       tri_equation = tri_equation >> 1;
                       if (x >= -tri_equation + col_center &&
                            x <=  tri_equation + col_center &&
                            y >= arrow_y[n] &&
                            y <  arrow_y[n] + BOX_SIZE) begin
                            if (y >= CATCH_ZONE_Y_START && y <= CATCH_ZONE_Y_END) begin
                                // Arrow is in catch zone
                                rgb_reg = active_catch_zone_color; // Green
                                arrow_in_catch_zone = 1;
                            end 
                            else begin
                                // Arrow outside catch zone
                                rgb_reg = arrow_color; // Red arrow
                            end
                        end
                   end
                   else if (arrow_col[n] == 1) begin
                       tri_equation = 20 - y + arrow_y[n];
                       tri_equation = tri_equation >> 1;
                       if (x >= -tri_equation + col_center &&
                            x <=  tri_equation + col_center &&
                            y >= arrow_y[n] &&
                            y <  arrow_y[n] + BOX_SIZE) begin
                            if (y >= CATCH_ZONE_Y_START && y <= CATCH_ZONE_Y_END) begin
                                // Arrow is in catch zone
                                rgb_reg = active_catch_zone_color; // Green
                                arrow_in_catch_zone = 1;
                            end 
                            else begin
                                // Arrow outside catch zone
                                rgb_reg = arrow_color; // Red arrow
                            end
                        end
                   end                   
            end
        end
            
            
            // Draw catch zone if no arrow is overlapping it at this pixel
            if (!arrow_in_catch_zone) begin
                if (y >= CATCH_ZONE_Y_START && y <= CATCH_ZONE_Y_END) begin
                    rgb_reg = catch_zone_color; // Yellow catch zone
                end
            end
        end else begin
            rgb_reg = 12'b0; // Outside of display area
        end
    end
    
    // Output assignments
    assign rgb = rgb_reg;
    
endmodule