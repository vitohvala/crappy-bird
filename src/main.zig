const std = @import("std");
const system = std.os.linux;

pub const Player = struct {
    x: i16,
    y: i16,
};

pub const Obstacle = struct {
    x: i16,
    y1: i16,
};

pub const MyCurses = struct {
    handle: system.fd_t = std.io.getStdIn().handle,
    old_term: std.posix.termios,
    std_out: @TypeOf(std.io.getStdOut().writer()) = std.io.getStdOut().writer(),
    width: i16 = undefined,
    height: i16 = undefined,

    const Self = @This();

    pub fn term_size(self: *Self) !void {
        var ws: std.posix.winsize = undefined;

        const err = system.ioctl(self.handle, system.T.IOCGWINSZ, @intFromPtr(&ws));
        if (std.posix.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }

        self.width = @as(i16, @intCast(ws.col));
        self.height = @as(i16, @intCast(ws.row));
    }

    pub fn enable_raw(self: *Self) !void {
        self.old_term = try std.posix.tcgetattr(self.handle);
        var term = self.old_term;
        term.lflag.ICANON = false;
        term.lflag.ECHO = false;

        term.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        term.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(self.handle, .FLUSH, term);
    }

    pub fn disable_raw(self: *Self) !void {
        try std.posix.tcsetattr(self.handle, .DRAIN, self.old_term);
    }

    pub fn hide_cursor(self: *Self) !void {
        try self.std_out.print("\x1b[?25l", .{});
    }

    pub fn show_cursor(self: *Self) !void {
        try self.std_out.print("\x1b[?25h", .{});
    }

    pub fn clear(self: *Self) !void {
        try self.std_out.print("\x1b[2J", .{});
        try self.std_out.print("\x1b[H", .{});
    }

    pub fn disable_wrap(self: *Self) !void {
        try self.std_out.print("\x1b[?7l", .{});
    }

    pub fn smcup(self: *Self) !void {
        try self.std_out.print("\x1b[?1049h", .{});
    }

    pub fn rmcup(self: *Self) !void {
        try self.std_out.print("\x1b[?1049l", .{});
    }

    pub fn enable_wrap(self: *Self) !void {
        try self.std_out.print("\x1b[?7h", .{});
    }

    pub fn init(self: *Self) !void {
        try self.term_size();
        try self.smcup();
        try self.clear();
        try self.enable_raw();
        try self.disable_wrap();
        try self.hide_cursor();
    }

    pub fn deinit(self: *Self) !void {
        try self.disable_raw();
        try self.enable_wrap();
        try self.show_cursor();
        try self.std_out.print("\x1b[0m", .{});
        try self.rmcup();
    }
};

pub fn procces_keys(quit: *bool, player: *Player) !void {
    const stdin = std.io.getStdIn().reader();
    var buf: [4]u8 = undefined;
    const nread = try stdin.read(&buf);
    std.debug.assert(nread >= 0);

    if (nread == 1) {
        switch (buf[0]) {
            'q' => quit.* = true,
            32 => {
                if (player.y > 2) player.y -= 3;
            },
            else => {},
        }
    }
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    var term = MyCurses{ .old_term = undefined };
    try term.init();
    defer term.deinit() catch {};
    var quit: bool = false;
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    var player = Player{ .x = 1, .y = 1 };

    var obstacle: [10]Obstacle = undefined;

    obstacle[0].x = term.width;
    obstacle[0].y1 = rand.intRangeAtMost(i16, -5, 10);
    for (1..obstacle.len) |i| {
        obstacle[i].x = obstacle[i - 1].x + @divFloor(term.width, 5);
        obstacle[i].y1 = rand.intRangeAtMost(i16, -5, 10);
    }

    var frame: usize = 0;
    var dead: bool = false;

    var index_o: usize = obstacle.len - 1;
    try bw.flush();
    while (!quit) {
        try term.clear();
        try term.term_size();

        if (dead) {
            try term.std_out.print("\x1b[{d};{d}H", .{ @divFloor(term.height, 2) - 1, @divFloor(term.width, 2) - 2 });
            try term.std_out.print("\x1b[38;5;123mDEAD\x1b[m", .{});
            if (frame > 60) {
                frame = 0;
                dead = false;
                obstacle[0].x = term.width;
                obstacle[0].y1 = rand.intRangeAtMost(i16, -5, 10);
                for (1..obstacle.len) |i| {
                    obstacle[i].x = obstacle[i - 1].x + @divFloor(term.width, 5);
                    obstacle[i].y1 = rand.intRangeAtMost(i16, -5, 10);
                }
                player.x = 1;
                player.y = 1;
                index_o = obstacle.len - 1;
            } else {
                frame += 1;
            }
        } else {
            if (player.x < @divFloor(term.width, 5)) player.x += 1;
            if (player.y < term.height - 1) player.y += 1;

            if (player.y > term.height - 2) dead = true;

            for (0..obstacle.len) |index| {
                obstacle[index].x -= 1;
                if (obstacle[index].x < -10) {
                    obstacle[index].x = obstacle[index_o].x + @divFloor(term.width, 5);
                    index_o += 1;
                    if (index_o > 9) index_o = 0;
                }
                if (player.x < (obstacle[index].x + 10) and
                    (player.x + 4) > obstacle[index].x and
                    (player.y <= ((@divFloor(term.height, 3)) + obstacle[index].y1) or player.y >= (@divFloor(term.height, 3)) + (obstacle[index].y1 + 10)))
                {
                    dead = true;
                    //quit = true;
                }
            }

            try procces_keys(&quit, &player);

            try term.std_out.print("\x1b[{d};{d}H", .{ player.y, player.x });
            try term.std_out.print("\x1b[48;5;123m    \x1b[m", .{});
            try term.std_out.print("\x1b[{d};{d}H", .{ player.y + 1, player.x });
            try term.std_out.print("\x1b[48;5;123m    \x1b[m", .{});

            for (1..@as(usize, @intCast(term.height + 1))) |y| {
                for (0..obstacle.len) |index| {
                    if (y < @divFloor(term.height, 3) + obstacle[index].y1 or @divFloor(term.height, 3) + (obstacle[index].y1 + 10) < y) {
                        try term.std_out.print("\x1b[{d};{d}H", .{ y, obstacle[index].x });
                        if (obstacle[index].x < 1) {
                            var i: i16 = 1;
                            while (i < obstacle[index].x + 10) {
                                try term.std_out.print("\x1b[48;5;123m \x1b[m", .{});
                                i += 1;
                            }
                        } else if (obstacle[index].x < term.width) {
                            try term.std_out.print("\x1b[48;5;123m          \x1b[m", .{});
                        }
                    }
                }
            }
        }

        std.time.sleep(std.time.ns_per_s * 0.09);
    }
    try bw.flush();
}
