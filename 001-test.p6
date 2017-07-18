use v6.c;
use lib 'lib';
use ActiveRecord;

class User is ActiveRecord {
    
    submethod BUILD {
        self.has-many: 'pages';
    }
}

class Page is ActiveRecord {
    
    submethod BUILD {
        self.belongs-to: 'user';
    }
}

sub MAIN {
    my $user = User.find(1);
    say $user.fname;
    my @pages = $user.pages;
    say @pages;
    my $page = $user.pages.first;
    say $page;
    say $page.user;
}
