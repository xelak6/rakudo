use lib <t/packages/>;
use Test;
use Test::Helpers;

plan 8;

subtest 'Supply.interval with negative value warns' => {
    plan 2;
    CONTROL { when CX::Warn {
        like .message, /'Minimum timer resolution is 1ms'/, 'useful warning';
        .resume;
    }}
    react whenever Supply.interval(-100) {
        pass "intervaled code ran";
        done;
    }
}

if $*DISTRO.is-win {
    skip 'is-run code is too complex to run on Windows (RT#132258)';
}
else {
    subtest 'no useless-use warning on return when KEEP/UNDO phasers used' => {
        plan 3;
        is-run ｢
            if  1 { LEAVE 42.uc; Any }; if  1 { LEAVE 42.uc; 42  };
            for 1 { LEAVE 42.uc; Any }; for 1 { LEAVE 42.uc; 42  };
        ｣, :err{ 2 == .comb: 'Useless use' },
            'we get warnings with phasers that do not care about return value';

        is-run ｢
            if  1 { KEEP 42.uc; Any }; if  1 { KEEP 42.uc; 42  };
            for 1 { KEEP 42.uc; Any }; for 1 { KEEP 42.uc; 42  };
        ｣, :err(''), 'no warnings with KEEP phaser';

        is-run ｢
            if  1 { UNDO 42.uc; Any }; if  1 { UNDO 42.uc; 42  };
            for 1 { UNDO 42.uc; Any }; for 1 { UNDO 42.uc; 42  };
        ｣, :err(''), 'no warnings with UNDO phaser';
    }
}

if $*DISTRO.is-win {
    skip 'is-run code is too complex to run on Windows (RT#132258)';
}
else {
    subtest 'no useless-use warning in andthen/notandthen/orelse/ chains' => {
        plan 2;
        is-run ｢
            1 notandthen 2 notandthen 3  notandthen 4;
            5 andthen    6 andthen    7  andthen    8;
            9 orelse     10 orelse    11 orelse     12;
        ｣, :err{ 3 == .comb: 'Useless use' },
            'we get warnings when last value is useless';

        is-run ｢
            2 notandthen 2 notandthen 2 notandthen 2.uc;
            2 andthen    2 andthen    2 andthen    2.uc;
            2 orelse     2 orelse     2 orelse     2.uc;
        ｣, 'no warnings when last value is useful';
    }
}

# RT #131305
is-run ｢
    sub prefix:<ᔑ> (Pair $p --> Pair) is tighter(&postcircumfix:<[ ]>) {};
    print postcircumfix:<[ ]>(<foo bar ber>, 1)
｣, :out<bar>, 'no spurious warnings when invoking colonpaired routine';

# RT #131251
is-run ｢my $a; $a [R~]= "b"; $a [Z~]= "b"; $a [X~]= "b"｣,
    'metaops + metaassign op do not produce spurious warnings';

# RT # 131331
# RT # 131123
is-run ｢my $ = ^2 .grep: {try 1 after 0}; my $ = {try 5 == 5}()｣,
    'no spurious warnings with `try` thunks in blocks';

is-run ｢my @a; sink @a; my $b := gather { print 'meow' }; sink $b｣,
    :out<meow>, 'no warnings when sinking variables';

is-run ｢use experimental :macros; macro z($) { quasi {} };
    z $; z <x>; print "pass"｣, :out<pass>,
    'args to macros do not cause useless use warnings';

# vim: ft=perl6 expandtab sw=4
