    my role Shaped1Array[::TValue] does ShapedArray[TValue] {
        multi method AT-POS(::?CLASS:D: int \one) is raw {
            nqp::ifnull(
              nqp::atpos(
                nqp::getattr(self,List,'$!reified'),
                one),
              self!AT-POS-CONTAINER(one)
            )
        }
        multi method AT-POS(::?CLASS:D: Int:D \one) is raw {
            nqp::ifnull(
              nqp::atpos(
                nqp::getattr(self,List,'$!reified'),
                one),
              self!AT-POS-CONTAINER(one)
            )
        }
        method !AT-POS-CONTAINER(int \one) is raw {
            nqp::p6bindattrinvres(
              (my $scalar := nqp::p6scalarfromdesc(
                nqp::getattr(self,Array,'$!descriptor'))),
              Scalar,
              '$!whence',
              -> { nqp::bindpos(
                     nqp::getattr(self,List,'$!reified'),
                     one, $scalar) }
            )
        }

        multi method STORE(::?CLASS:D: Iterable:D \in) {
            nqp::stmts(
              (my \list := nqp::getattr(self,List,'$!reified')),
              (my \desc := nqp::getattr(self,Array,'$!descriptor')),
              (my \iter := in.iterator),
              (my int $i = -1),
              nqp::until(
                nqp::eqaddr((my $pulled := iter.pull-one),IterationEnd),
                nqp::ifnull(
                  nqp::atpos(list,($i = nqp::add_i($i,1))),
                  nqp::bindpos(list,$i,nqp::p6scalarfromdesc(desc))
                ) = $pulled
              ),
              self
            )
        }
        multi method STORE(::?CLASS:D: Mu \item) {
            nqp::ifnull(
              nqp::atpos(nqp::getattr(self,List,'$!reified'),0),
              nqp::bindpos(nqp::getattr(self,List,'$!reified'),0,
                nqp::p6scalarfromdesc(nqp::getattr(self,Array,'$!descriptor')))
            ) = item
        }

        multi method keys(::?CLASS:D:) {
            Seq.new(
              Rakudo::Internals.IntRangeIterator(0,self.shape.AT-POS(0) - 1))
        }
        method reverse(::?CLASS:D:) {
            Rakudo::Internals.ReverseListToList(
              self, self.new(:shape(self.shape)))
        }
        method rotate(::?CLASS:D: Int(Cool) $rotate = 1) {
            Rakudo::Internals.RotateListToList(
              self, $rotate, self.new(:shape(self.shape)))
        }
    }

# vim: ft=perl6 expandtab sw=4