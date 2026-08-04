package router

import (
	"github.com/kataras/iris/v12"
	"iptv-spider-sh/router/api"
)

func InitRouters(app *iris.Application) {
	registerMacros(app)
	app.Get("/tv.m3u", api.GenerateTiviMateM3u)
	// 中间件注册
	//app.UseRouter(middleware.Cors())
	// 各个路由分组
	apiRouterGroup := app.Party("/api")
	{
		api.InitApiRouters(apiRouterGroup)
	}

}
