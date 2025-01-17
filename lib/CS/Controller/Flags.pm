package CS::Controller::Flags;
use Mojo::Base 'Mojolicious::Controller';

sub put {
  my $c = shift->render_later;

  my ($game_status) = $c->app->model('util')->game_status;
  unless ($game_status == 1) {
    return $c->render(json => {status => \0, msg => 'Game is not active for now'}, status => 400);
  }

  if ($c->req->body_size > 16 * 1024) {
    return $c->render(json => {status => \0, msg => 'Message is too big'}, status => 400);
  }

  my $token = $c->req->headers->header('X-Team-Token') // '';
  return $c->render(json => {status => \0, msg => "Invalid token '$token'"}, status => 400)
    unless my $team_id = $c->app->tokens->{$token};

  my $flags = $c->req->json // [];
  my $results = [];

  my $do;
  $do = sub {
    my $flag = shift @$flags;

    unless ($flag) {
      undef $do;
      $c->render(json => $results);
      return;
    }

    $c->model('flag')->accept(
      $team_id, $flag,
      sub {
        my $msg = $_[0]->{ok} ? $_[0]->{message} : $_[0]->{error};
        push @$results, {flag => $flag, status => \$_[0]->{ok}, msg => $msg};
        $do->();
      }
    );
  };

  $do->();
}

sub list {
  my $c = shift;

  my $token = $c->req->headers->header('X-Team-Token') // '';
  return $c->render(json => {status => \0, msg => 'Invalid token'}, status => 400)
    unless my $team_id = $c->app->tokens->{$token};

  return $c->render(json => {status => \0, msg => 'Invalid service_id'}, status => 400)
    unless my $service = $c->app->services->{$c->param('service_id') // $c->param('service')};

  my $flags = $c->pg->db->query(q{
    select
      t.id,
      array_agg(public_id) filter (where public_id is not null) as flag_ids
    from (
      select * from flags
      where
        service_id = ? and team_id != ? and
        public_id is not null and not expired
    ) as f
    right join teams as t on t.id = f.team_id
    group by t.id
  }, $service->{id}, $team_id);
  my $flag_ids = $flags->hashes->reduce(sub {
    my $team = $c->app->teams->{$b->{id}};
    $a->{$b->{id}}{host} = $c->model('util')->get_service_host($team, $service);
    $a->{$b->{id}}{flag_ids} = $b->{flag_ids} // [];
    $a;
  }, {});

  $c->render(json => {
    flag_id_description => $service->{public_flag_description},
    flag_ids => $flag_ids
  });
}

1;
