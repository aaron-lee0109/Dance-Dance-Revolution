module debounce(
    input clk,
    input rst,
    input button_in,
    output reg button_out
    );

    reg [15:0] counter;
    reg button_sync_0, button_sync_1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            button_sync_0 <= 0;
            button_sync_1 <= 0;
            button_out <= 0;
            counter <= 0;
        end else begin
            button_sync_0 <= button_in;
            button_sync_1 <= button_sync_0;

            if (button_sync_1 == 1'b0) begin
                counter <= 0;
                button_out <= 0;
            end else begin
                if (counter < 16'hFFFF)
                    counter <= counter + 1;
                if (counter == 16'hFFFF)
                    button_out <= 1;
            end
        end
    end
endmodule