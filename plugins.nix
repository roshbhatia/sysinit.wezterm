{ pkgs }: {
  tabline = pkgs.fetchFromGitHub {
    owner = "michaelbrusegard";
    repo = "tabline.wez";
    rev = "5e148f08f134e317bbfe75b26f8a23b0102cb621";
    hash = "sha256-G5sFPIJ2SDLKjeiuauJfzu3JgvViwoe9RLhYAScaHbs=";
  };
  agent-deck = pkgs.applyPatches {
    src = pkgs.fetchFromGitHub {
      owner = "Eric162";
      repo = "wezterm-agent-deck";
      rev = "bd5a57e7806032998e6cae56ade67b72a08b7868";
      hash = "sha256-nb5eCStxsgLBgZSNZjOBMYLNbv0haxXM+6609FywnwE=";
    };
    patches = [ ./patches/agent-deck-idle-detection.patch ];
  };
  warp = pkgs.fetchFromGitHub {
    owner = "sravioli";
    repo = "warp.wz";
    rev = "ccc6816fff3174bd826ab1a7154fb8469a8e4cdd";
    hash = "sha256-GRYSLrZXmGSJqXqfAvolBwsu+o1AYEBSUYBVGlLkLqg=";
  };
  ribbon = pkgs.fetchFromGitHub {
    owner = "sravioli";
    repo = "ribbon.wz";
    rev = "e2735090f8e5e2815429c86f1816260523b86494";
    hash = "sha256-nfSHZnAkd/CNk8GFm6QoBZ36zPhcR5le70geNRpk7J0=";
  };
  sigil = pkgs.fetchFromGitHub {
    owner = "sravioli";
    repo = "sigil.wz";
    rev = "1e58c730dcbf8bfdcd32cdada3484a1d673e0464";
    hash = "sha256-tEspBNdQqGif5DQV8JAzVQRdW0Hl6ykdSMmx+BqNj90=";
  };
  log = pkgs.fetchFromGitHub {
    owner = "sravioli";
    repo = "log.wz";
    rev = "43dc5e48b8962e4636c22be3d67ef3a8b8eca795";
    hash = "sha256-+EvwhQIQTe9QqC7qEG1OnEkCfPux+E5UH6xBEocTk4M=";
  };
  memo = pkgs.fetchFromGitHub {
    owner = "sravioli";
    repo = "memo.wz";
    rev = "f5cdebca623809f7e61563a48b1679c81d32b148";
    hash = "sha256-SnI3n2oi0txKVK+v55aA4TVx0rcmli+okWUdzuy6SGU=";
  };
  lantern = pkgs.applyPatches {
    src = pkgs.fetchFromGitHub {
      owner = "sravioli";
      repo = "lantern.wz";
      rev = "cfe4acb1b04b81a16410a66283477d68c98a3375";
      hash = "sha256-ncxG9quSnpueWPZhEMC4DS63/9m3ayLX6s7g9VoMMIg=";
    };
    patches = [ ./patches/lantern-deps-loader.patch ];
  };
  workspace-manager = pkgs.fetchFromGitHub {
    owner = "ryanmsnyder";
    repo = "workspace-manager.wezterm";
    rev = "2aa02b17b3555035e329a479e6f981027d611b15";
    hash = "sha256-p+J/ilHkrauaviMNH6zEeFpAXLKAistSrJpRNCftqoI=";
  };
}
