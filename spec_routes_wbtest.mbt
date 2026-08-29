///|
test "api parser: four route arities and a grouped type block" {
  let src =
    #|syntax = "v1"
    #|
    #|type (
    #|  LoginReq {
    #|    name string `json:"name"`
    #|  }
    #|  LoginResp {
    #|    token string `json:"token"`
    #|  }
    #|)
    #|
    #|service demo-api {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @handler upload
    #|  post /upload (LoginReq)
    #|
    #|  @handler list
    #|  get /list returns (LoginResp)
    #|
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|
    #|  get /legacy legacyHandler "legacy summary"
    #|}
  let spec = parse(src)
  let mut names = ""
  for t in spec.types {
    names = names + t.name + ";"
  }
  inspect(names, content="LoginReq;LoginResp;")
  let mut sig = ""
  for r in spec.routes {
    sig = sig +
      r.verb +
      " " +
      r.path +
      " h=" +
      r.handler +
      " q=" +
      r.req +
      " s=" +
      r.resp +
      "\n"
  }
  inspect(
    sig,
    content=(
      #|get /ping h=ping q= s=
      #|post /upload h=upload q=LoginReq s=
      #|get /list h=list q= s=LoginResp
      #|post /login h=login q=LoginReq s=LoginResp
      #|get /legacy h=legacyHandler q= s=
      #|
    ),
  )
}
