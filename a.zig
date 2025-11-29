const Error = error{ abc, def, ghi };

fn a() !void {
    const ab = Error;
    switch (ab) {}
}
