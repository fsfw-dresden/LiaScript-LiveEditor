import { createApp } from 'vue'
import Index from './views/Index.vue'
import Edit from './views/Edit.vue'
import File from './views/File.vue'
import Zip from './views/Zip.vue'
import Tutor from './views/Tutor.vue'
import GitHubExporter from './views/Export/GitHub.vue'
import AudioRecorder from 'vue3-mic-recorder'
import { randomString } from './ts/utils'

var app

const pathToRegex = (path) =>
  new RegExp('^' + path.replace(/\//g, '\\/').replace(/:\w+/g, '(.+)') + '$')

const getParams = (match) => {
  const values = match.result.slice(1)
  const keys = Array.from(match.route.path.matchAll(/:(\w+)/g)).map(
    (result) => result[1]
  )

  let params = Object.fromEntries(
    keys.map((key, i) => {
      return [key, values[i]]
    })
  )

  if (match.params) {
    params = { ...params, ...match.params }
  }

  return params
}

export const navigateTo = (url: string, replace?: boolean) => {
  if (replace) {
    history.replaceState(null, '', url)
  } else {
    history.pushState(null, '', url)
  }
  router()
}

const router = async () => {
  if (location.pathname.startsWith('liascript')) {
    return
  }

  if (window.location.search.startsWith('?%2F')) {
    window.location.search = decodeURIComponent(window.location.search)
    return
  }

  const routes = [
    { path: '/', view: Index },
    { path: '/edit', redirect: '?/edit/' + randomString(24) },
    { path: '/edit/:storageId/:connection', view: Edit },
    { path: '/edit/:storageId', view: Edit },
    {
      path: '/embed/code/edit/:zipCode',
      view: Zip,
      params: { embed: true, mode: -1 },
    },
    {
      path: '/embed/code/preview/:zipCode',
      view: Zip,
      params: { embed: true, mode: 1 },
    },
    { path: '/embed/code/:zipCode', view: Zip, params: { embed: true } },
    { path: '/embed/file/:fileUrl', view: File, params: { embed: true } },

    { path: '/show/code/:zipCode', view: Zip },
    { path: '/show/file/:fileUrl', view: File },
    { path: '/tutor/:fileUrl', view: Tutor },
    {
      path: '/export/github/&code=:code&state=:stepId2',
      view: GitHubExporter,
    },
    {
      path: '/export/github/:stepId1',
      view: GitHubExporter,
    },
  ]

  const potentialMatches = routes.map((route) => {
    return {
      route: route,
      result: location.search.slice(1).match(pathToRegex(route.path)),
      redirect: route.redirect,
      params: route.params,
    }
  })

  let match = potentialMatches.find(
    (potentialMatches) => potentialMatches.result !== null
  )

  if (!match) {
    match = {
      route: routes[0],
      result: [location.search],
    }
  }

  if (match.redirect) {
    navigateTo(match.redirect, true)
    return
  }

  const params = getParams(match)
  const view = match.route.view

  app?.unmount()

  app = createApp(view, params)
  app.use(AudioRecorder)

  app.mount(document.body)
}

window.addEventListener('popstate', router)

document.addEventListener('DOMContentLoaded', () => {
  document.body.addEventListener('click', (e) => {
    if (e.target && e.target.matches('[data-link]')) {
      e.preventDefault()
      navigateTo(e.target.href)
    }
  })

  router()
})
