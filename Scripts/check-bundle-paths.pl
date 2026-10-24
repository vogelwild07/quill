#!/usr/bin/perl
# Sucht Pfade aus Benutzerordnern in einem App-Bundle (ADR-022), für make-release.sh.
# Aufruf: Scripts/check-bundle-paths.pl <eigener Benutzername> <Quill.app>
# Erlaubt sind nur Pfade vom Build-Rechner der vorgebauten Rust-Bibliothek von
# automerge-swift, nie mit dem eigenen Namen:
#   /Users/<Name>/.cargo/registry/src/index.crates.io-<Hash>/   (Quellen der Rust-Pakete)
#   /Users/<Name>/.rustup/toolchains/<Toolchain>-aarch64-apple-darwin   (Rust selbst)
#   /Users/<Name>/<Ordner>/automerge-swift/rust/   (Build-Ordner der Bibliothek) Gibt jeden anderen Fund aus; Exit 1 bei einem Fund, 2 bei einem Lesefehler.
use strict;
use warnings;
use File::Find;

my ($user, $app) = @ARGV;
die "Aufruf: check-bundle-paths.pl <Benutzername> <App>\n" unless defined $app && length $user;
my $allowed = qr{\G/Users/([A-Za-z0-9._-]+)/(?:
      \.cargo/registry/src/index\.crates\.io-[0-9a-f]+/
    | \.rustup/toolchains/[A-Za-z0-9._-]+-aarch64-apple-darwin
    | (?:[A-Za-z0-9._-]+/)+automerge-swift/rust/
)}x;
my ($found, $unreadable, $skipped) = (0, 0, 0);

find({ no_chdir => 1, wanted => sub {
    return unless -f $_ && !-l $_;
    my $file = $_;
    open(my $fh, '<:raw', $file) or do { warn "nicht lesbar: $file\n"; $unreadable = 1; return };
    local $/;
    my $data = <$fh>;
    close $fh;
    if (index($data, $user) >= 0) {
        print "$file: enthält den eigenen Benutzernamen\n";
        $found = 1;
    }
    while ($data =~ m{/Users/}g) {
        my $start = pos($data) - length('/Users/');
        pos($data) = $start;
        if ($data =~ m{$allowed}gc && $1 ne $user) {
            $skipped++;
            next;
        }
        my $text = substr($data, $start, 80);
        $text =~ s/[^[:print:]].*//s;
        print "$file: $text\n";
        $found = 1;
        pos($data) = $start + length('/Users/');
    }
}}, $app);

print "Erlaubte Pfade aus der vorgebauten Automerge-Bibliothek: $skipped\n";
exit 2 if $unreadable;
exit $found;
