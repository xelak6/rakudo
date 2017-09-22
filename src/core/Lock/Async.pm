# An asynchronous lock provides a non-blocking non-reentrant mechanism for
# mutual exclusion. The lock method returns a Promise, which will already be
# Kept if nothing was holding the lock already, so execution can proceed
# immediately. For performance reasons, in this case it returns a singleton
# Promise instance. Otherwise, a Promise in planned state will be returned,
# and Kept once the lock has been unlocked by its current holder. The lock
# and unlock do not need to take place on the same thread; that's why it's not
# reentrant.

my class X::Lock::Async::NotLocked is Exception {
    method message() {
        "Cannot unlock a Lock::Async that is not currently locked"
    }
}

my class Lock::Async {
    # The Holder class is an immutable object. A type object represents an
    # unheld lock, an instance represents a held lock, and it has a queue of
    # vows to be kept on unlock.
    my class Holder {
        has $!queue;

        method queue-vow(\v) {
            my $new-queue := $!queue.DEFINITE
                ?? nqp::clone($!queue)
                !! nqp::list();
            nqp::push($new-queue, v);
            nqp::p6bindattrinvres(nqp::create(Holder), Holder, '$!queue', $new-queue)
        }

        method waiter-queue-length() {
            nqp::elems($!queue)
        }

        # Assumes it won't be called if there is no queue (SINGLE_HOLDER case
        # in unlock()) 
        method head-vow() {
            nqp::atpos($!queue, 0)
        }

        # Assumes it won't be called if the queue only had one item in it (to
        # mantain SINGLE_HOLDER fast path usage)
        method without-head-vow() {
            my $new-queue := nqp::clone($!queue);
            nqp::shift($new-queue);
            nqp::p6bindattrinvres(nqp::create(Holder), Holder, '$!queue', $new-queue)
        }
    }

    # Base states for Holder
    my constant NO_HOLDER = Holder;
    my constant SINGLE_HOLDER = Holder.new;

    # The current holder record, with waiters queue, of the lock.
    has Holder $!holder = Holder;

    # Singleton Promise to be used when there's no need to wait.
    my \KEPT-PROMISE := do {
        my \p = Promise.new;
        p.keep(True);
        p
    }

    method lock(Lock::Async:D: --> Promise) {
        loop {
            my $holder := ⚛$!holder;
            if $holder.DEFINITE {
                my $p := Promise.new;
                my $v := $p.vow;
                my $holder-update = $holder.queue-vow($v);
                if cas($!holder, $holder, $holder-update) =:= $holder {
                    return $p;
                }
            }
            else {
                if cas($!holder, NO_HOLDER, SINGLE_HOLDER) =:= NO_HOLDER {
                    # Successfully acquired and we're the only holder
                    return KEPT-PROMISE;
                }
            }
        }
    }

    method unlock(Lock::Async:D: --> Nil) {
        loop {
            my $holder := ⚛$!holder;
            if $holder =:= SINGLE_HOLDER {
                # We're the single holder and there's no wait queue.
                if cas($!holder, SINGLE_HOLDER, NO_HOLDER) =:= SINGLE_HOLDER {
                    # Successfully released to NO_HOLDER state.
                    return;
                }
            }
            elsif $holder.DEFINITE {
                my int $queue-length = $holder.waiter-queue-length();
                my $v := $holder.head-vow;
                if $queue-length == 1 {
                    if cas($!holder, $holder, SINGLE_HOLDER) =:= $holder {
                        # Successfully released; keep the head vow, thus
                        # giving the lock to the next waiter.
                        $v.keep(True);
                        return;
                    }
                }
                else {
                    my $new-holder := $holder.without-head-vow();
                    if cas($!holder, $holder, $new-holder) =:= $holder {
                        # Successfully released and installed remaining queue;
                        # keep the head vow which we successfully removed.
                        $v.keep(True);
                        return;
                    }
                }
            }
            else {
                die X::Lock::Async::NotLocked.new;
            }
        }
    }

    method protect(Lock::Async:D: &code) {
        my int $acquired = 0;
        $*AWAITER.await(self.lock());
        $acquired = 1;
        LEAVE self.unlock() if $acquired;
        code()
    }

    # This either runs the code now if we can obtain the lock, releasing the
    # lock afterwards, or queues the code to run if a recursive use of the
    # lock is observed. It relies on all users of the lock to use it through
    # this method only. This is useful for providing back-pressure while also
    # avoiding code deadlocking on itself by providing a way for it to get run
    # later on. Returns Nil if the code was run now (maybe after blocking), or
    # a Promise if it was queued for running later.
    method protect-or-queue-on-recursion(Lock::Async:D: &code) {
        my $try-acquire = self.lock();
        if $try-acquire {
            # We could acquire the lock. Run the code right now.
            LEAVE self.unlock();
            self!run-with-updated-recursion-list(&code);
            Nil
        }
        elsif (@*LOCK-ASYNC-RECURSION-LIST // Empty).first(* === self) {
            # Lock is already held on the stack, so we're recursing. Queue.
            $try-acquire.then({
                LEAVE self.unlock();
                self!run-with-updated-recursion-list(&code);
            });
        }
        else {
            # Lock is held but by something else. Await it's availability.
            my int $acquired = 0;
            $*AWAITER.await($try-acquire);
            $acquired = 1;
            LEAVE self.unlock() if $acquired;
            self!run-with-updated-recursion-list(&code);
            Nil
        }
    }

    method !run-with-updated-recursion-list(&code) {
        my @new-held = @*LOCK-ASYNC-RECURSION-LIST // ();
        @new-held.push(self);
        {
            my @*LOCK-ASYNC-RECURSION-LIST := @new-held;
            code();
        }
    }

    method with-lock-hidden-from-recursion-check(&code) {
        my @new-held = (@*LOCK-ASYNC-RECURSION-LIST // ()).grep(* !=== self);
        {
            my @*LOCK-ASYNC-RECURSION-LIST := @new-held;
            code();
        }
    }
}
