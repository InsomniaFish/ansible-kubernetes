{{ $var := .externalURL}}{{ range $k,$v:=.alerts }}{{if eq $v.status "resolved"}}**[Prometheus恢复信息]()**
状态：{{$v.status}}
**{{$v.labels.alertname}}**
告警级别：{{ if $v.labels.severity }}{{$v.labels.severity}}{{else if $v.labels.level }}{{$v.labels.level}}{{else}}unknown{{end}}
命名空间：{{$v.labels.namespace}}
Pod：{{$v.labels.pod}}
节点：{{ if $v.labels.node }}{{$v.labels.node}}{{else if $v.labels.nodename }}{{$v.labels.nodename}}{{else}}{{$v.labels.instance}}{{end}}
开始时间：{{$v.startsAt}}
结束时间：{{$v.endsAt}}
摘要：{{$v.annotations.summary}}
详情：{{$v.annotations.description}}{{else}}**[Prometheus告警信息]()**
状态：{{$v.status}}
**{{$v.labels.alertname}}**
告警级别：{{ if $v.labels.severity }}{{$v.labels.severity}}{{else if $v.labels.level }}{{$v.labels.level}}{{else}}unknown{{end}}
命名空间：{{$v.labels.namespace}}
Pod：{{$v.labels.pod}}
节点：{{ if $v.labels.node }}{{$v.labels.node}}{{else if $v.labels.nodename }}{{$v.labels.nodename}}{{else}}{{$v.labels.instance}}{{end}}
开始时间：{{$v.startsAt}}
摘要：{{$v.annotations.summary}}
详情：{{$v.annotations.description}}{{end}}
{{ end }}
{{ $first := index .alerts 0 }}[*** 点我屏蔽该告警]({{$var}}/#/silences/new?filter=%7Balertname%3D%22{{$first.labels.alertname}}%22%7D)
