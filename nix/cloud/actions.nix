{
  cell,
  inputs,
}: {
  "ci-world/ci" = {
    task = "ci/build";
    io = ''
      let github = {
        #input:  "Github event"
        #repo:   "input-output-hk/ci-world"
        #branch: "ci-world-tests"
      }

      #lib: ios: [
        {#lib.io.github_push, github},
      ]

      // _lib: github: {
      //   #repo: "input-output-hk/ci-world"

      // pull_request: {}
      //   push: #branch: "ci-world-tests"
      // }
      // inputs: bitte: match: {
      //   github_event: string
      //   github_body: {
      //     pusher: {}
      //     deleted: false
      //     repository: full_name: "input-output-hk/bitte"
      //     head_commit: id:       string
      //     ref: =~"^refs/heads/bitte-tests$"
      //   }
      // }

      // output: [string]: {
      //   let bitte_event = inputs["bitte"].value.github_body
      //   bitte_revision: bitte_event.pull_request.head.sha | bitte_event.head_commit.id
      // }
    '';
  };

  # "cicero/cd" = {
  #   task = "cicero/deploy";
  #   io = ''
  #     _lib: github: push: #repo: "input-output-hk/cicero"

  #     inputs: ci: match: {
  #       ok: true
  #       revision: inputs."GitHub event".value.github_body.head_commit.id
  #     }
  #   '';
  # };
}
