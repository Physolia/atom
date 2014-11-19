path = require 'path'

{$, $$, WorkspaceView} = require 'atom'
fs = require 'fs-plus'
temp = require 'temp'

ThemeManager = require '../src/theme-manager'
Package = require '../src/package'

describe "ThemeManager", ->
  themeManager = null
  resourcePath = atom.getLoadSettings().resourcePath
  configDirPath = atom.getConfigDirPath()

  beforeEach ->
    themeManager = new ThemeManager({packageManager: atom.packages, resourcePath, configDirPath})

  afterEach ->
    themeManager.deactivateThemes()

  describe "theme getters and setters", ->
    beforeEach ->
      atom.packages.loadPackages()

    it 'getLoadedThemes get all the loaded themes', ->
      themes = themeManager.getLoadedThemes()
      expect(themes.length).toBeGreaterThan(2)

    it 'getActiveThemes get all the active themes', ->
      waitsForPromise ->
        themeManager.activateThemes()

      runs ->
        names = atom.config.get('core.themes')
        expect(names.length).toBeGreaterThan(0)
        themes = themeManager.getActiveThemes()
        expect(themes).toHaveLength(names.length)

  describe "when the core.themes config value contains invalid entry", ->
    it "ignores theme", ->
      atom.config.set 'core.themes', [
        'atom-light-ui'
        null
        undefined
        ''
        false
        4
        {}
        []
        'atom-dark-ui'
      ]

      expect(themeManager.getEnabledThemeNames()).toEqual ['atom-dark-ui', 'atom-light-ui']

  describe "::getImportPaths()", ->
    it "returns the theme directories before the themes are loaded", ->
      atom.config.set('core.themes', ['theme-with-index-less', 'atom-dark-ui', 'atom-light-ui'])

      paths = themeManager.getImportPaths()

      # syntax theme is not a dir at this time, so only two.
      expect(paths.length).toBe 2
      expect(paths[0]).toContain 'atom-light-ui'
      expect(paths[1]).toContain 'atom-dark-ui'

    it "ignores themes that cannot be resolved to a directory", ->
      atom.config.set('core.themes', ['definitely-not-a-theme'])
      expect(-> themeManager.getImportPaths()).not.toThrow()

  describe "when the core.themes config value changes", ->
    it "add/removes stylesheets to reflect the new config value", ->
      themeManager.onDidReloadAll reloadHandler = jasmine.createSpy()
      spyOn(atom.styles, 'getUserStyleSheetPath').andCallFake -> null

      waitsForPromise ->
        themeManager.activateThemes()

      runs ->
        reloadHandler.reset()
        atom.config.set('core.themes', [])

      waitsFor ->
        reloadHandler.callCount == 1

      runs ->
        reloadHandler.reset()
        expect($('style.theme')).toHaveLength 0
        atom.config.set('core.themes', ['atom-dark-ui'])

      waitsFor ->
        reloadHandler.callCount == 1

      runs ->
        reloadHandler.reset()
        expect($('style[group=theme]')).toHaveLength 2
        expect($('style[group=theme]:eq(0)').attr('source-path')).toMatch /atom-dark-ui/
        atom.config.set('core.themes', ['atom-light-ui', 'atom-dark-ui'])

      waitsFor ->
        reloadHandler.callCount == 1

      runs ->
        reloadHandler.reset()
        expect($('style[group=theme]')).toHaveLength 2
        expect($('style[group=theme]:eq(0)').attr('source-path')).toMatch /atom-dark-ui/
        expect($('style[group=theme]:eq(1)').attr('source-path')).toMatch /atom-light-ui/
        atom.config.set('core.themes', [])

      waitsFor ->
        reloadHandler.callCount == 1

      runs ->
        reloadHandler.reset()
        expect($('style[group=theme]')).toHaveLength 2
        # atom-dark-ui has an directory path, the syntax one doesn't
        atom.config.set('core.themes', ['theme-with-index-less', 'atom-dark-ui'])

      waitsFor ->
        reloadHandler.callCount == 1

      runs ->
        expect($('style[group=theme]')).toHaveLength 2
        importPaths = themeManager.getImportPaths()
        expect(importPaths.length).toBe 1
        expect(importPaths[0]).toContain 'atom-dark-ui'

  describe "when a theme fails to load", ->
    it "logs a warning", ->
      spyOn(console, 'warn')
      expect(-> atom.packages.activatePackage('a-theme-that-will-not-be-found')).toThrow()

  describe "::requireStylesheet(path)", ->
    it "synchronously loads css at the given path and installs a style tag for it in the head", ->
      themeManager.onDidChangeStylesheets stylesheetsChangedHandler = jasmine.createSpy("stylesheetsChangedHandler")
      themeManager.onDidAddStylesheet stylesheetAddedHandler = jasmine.createSpy("stylesheetAddedHandler")
      cssPath = atom.project.resolve('css.css')
      lengthBefore = $('head style').length

      themeManager.requireStylesheet(cssPath)
      expect($('head style').length).toBe lengthBefore + 1

      expect(stylesheetAddedHandler).toHaveBeenCalled()
      expect(stylesheetsChangedHandler).toHaveBeenCalled()

      element = $('head style[source-path*="css.css"]')
      expect(element.attr('source-path')).toBe themeManager.stringToId(cssPath)
      expect(element.text()).toBe fs.readFileSync(cssPath, 'utf8')
      expect(element[0].sheet).toBe stylesheetAddedHandler.argsForCall[0][0]

      # doesn't append twice
      themeManager.requireStylesheet(cssPath)
      expect($('head style').length).toBe lengthBefore + 1

      $('head style[id*="css.css"]').remove()

    it "synchronously loads and parses less files at the given path and installs a style tag for it in the head", ->
      lessPath = atom.project.resolve('sample.less')
      lengthBefore = $('head style').length
      themeManager.requireStylesheet(lessPath)
      expect($('head style').length).toBe lengthBefore + 1

      element = $('head style[source-path*="sample.less"]')
      expect(element.attr('source-path')).toBe themeManager.stringToId(lessPath)
      expect(element.text()).toBe """
      #header {
        color: #4d926f;
      }
      h2 {
        color: #4d926f;
      }

      """

      # doesn't append twice
      themeManager.requireStylesheet(lessPath)
      expect($('head style').length).toBe lengthBefore + 1
      $('head style[id*="sample.less"]').remove()

    it "supports requiring css and less stylesheets without an explicit extension", ->
      themeManager.requireStylesheet path.join(__dirname, 'fixtures', 'css')
      expect($('head style[source-path*="css.css"]').attr('source-path')).toBe themeManager.stringToId(atom.project.resolve('css.css'))
      themeManager.requireStylesheet path.join(__dirname, 'fixtures', 'sample')
      expect($('head style[source-path*="sample.less"]').attr('source-path')).toBe themeManager.stringToId(atom.project.resolve('sample.less'))

      $('head style[id*="css.css"]').remove()
      $('head style[id*="sample.less"]').remove()

    it "returns a disposable allowing styles applied by the given path to be removed", ->
      cssPath = require.resolve('./fixtures/css.css')

      expect($(document.body).css('font-weight')).not.toBe("bold")
      disposable = themeManager.requireStylesheet(cssPath)
      expect($(document.body).css('font-weight')).toBe("bold")

      themeManager.onDidRemoveStylesheet stylesheetRemovedHandler = jasmine.createSpy("stylesheetRemovedHandler")
      themeManager.onDidChangeStylesheets stylesheetsChangedHandler = jasmine.createSpy("stylesheetsChangedHandler")

      disposable.dispose()

      expect($(document.body).css('font-weight')).not.toBe("bold")

      expect(stylesheetRemovedHandler).toHaveBeenCalled()
      stylesheet = stylesheetRemovedHandler.argsForCall[0][0]
      expect(stylesheet instanceof CSSStyleSheet).toBe true
      expect(stylesheet.cssRules[0].selectorText).toBe 'body'

      expect(stylesheetsChangedHandler).toHaveBeenCalled()

  describe "base stylesheet loading", ->
    beforeEach ->
      atom.workspaceView = atom.views.getView(atom.workspace).__spacePenView
      atom.workspaceView.append $('<atom-text-editor>')
      atom.workspaceView.attachToDom()

      waitsForPromise ->
        themeManager.activateThemes()

    it "loads the correct values from the theme's ui-variables file", ->
      themeManager.onDidReloadAll reloadHandler = jasmine.createSpy()
      atom.config.set('core.themes', ['theme-with-ui-variables', 'theme-with-syntax-variables'])

      waitsFor ->
        reloadHandler.callCount > 0

      runs ->
        # an override loaded in the base css
        expect(atom.workspaceView.css("background-color")).toBe "rgb(0, 0, 255)"

        # from within the theme itself
        expect($("atom-text-editor").css("padding-top")).toBe "150px"
        expect($("atom-text-editor").css("padding-right")).toBe "150px"
        expect($("atom-text-editor").css("padding-bottom")).toBe "150px"

    describe "when there is a theme with incomplete variables", ->
      it "loads the correct values from the fallback ui-variables", ->
        themeManager.onDidReloadAll reloadHandler = jasmine.createSpy()
        atom.config.set('core.themes', ['theme-with-incomplete-ui-variables', 'theme-with-syntax-variables'])

        waitsFor ->
          reloadHandler.callCount > 0

        runs ->
          # an override loaded in the base css
          expect(atom.workspaceView.css("background-color")).toBe "rgb(0, 0, 255)"

          # from within the theme itself
          expect($("atom-text-editor").css("background-color")).toBe "rgb(0, 152, 255)"

    describe "theme classes on the workspace", ->
      it 'adds theme-* classes to the workspace for each active theme', ->
        expect(atom.workspaceView).toHaveClass 'theme-atom-dark-ui'

        themeManager.onDidReloadAll reloadHandler = jasmine.createSpy()
        atom.config.set('core.themes', ['theme-with-ui-variables', 'theme-with-syntax-variables'])

        waitsFor ->
          reloadHandler.callCount > 0

        runs ->
          # `theme-` twice as it prefixes the name with `theme-`
          expect(atom.workspaceView).toHaveClass 'theme-theme-with-ui-variables'
          expect(atom.workspaceView).toHaveClass 'theme-theme-with-syntax-variables'
          expect(atom.workspaceView).not.toHaveClass 'theme-atom-dark-ui'
          expect(atom.workspaceView).not.toHaveClass 'theme-atom-dark-syntax'

  describe "when the user stylesheet changes", ->
    it "reloads it", ->
      [stylesheetRemovedHandler, stylesheetAddedHandler, stylesheetsChangedHandler] = []
      userStylesheetPath = path.join(temp.mkdirSync("atom"), 'styles.less')
      fs.writeFileSync(userStylesheetPath, 'body {border-style: dotted !important;}')
      spyOn(atom.styles, 'getUserStyleSheetPath').andReturn userStylesheetPath

      waitsForPromise ->
        themeManager.activateThemes()

      runs ->
        themeManager.onDidChangeStylesheets stylesheetsChangedHandler = jasmine.createSpy("stylesheetsChangedHandler")
        themeManager.onDidRemoveStylesheet stylesheetRemovedHandler = jasmine.createSpy("stylesheetRemovedHandler")
        themeManager.onDidAddStylesheet stylesheetAddedHandler = jasmine.createSpy("stylesheetAddedHandler")
        spyOn(themeManager, 'loadUserStylesheet').andCallThrough()

        expect($(document.body).css('border-style')).toBe 'dotted'
        fs.writeFileSync(userStylesheetPath, 'body {border-style: dashed}')

      waitsFor ->
        themeManager.loadUserStylesheet.callCount is 1

      runs ->
        expect($(document.body).css('border-style')).toBe 'dashed'

        expect(stylesheetRemovedHandler).toHaveBeenCalled()
        expect(stylesheetRemovedHandler.argsForCall[0][0].cssRules[0].style.border).toBe 'dotted'

        expect(stylesheetAddedHandler).toHaveBeenCalled()
        expect(stylesheetAddedHandler.argsForCall[0][0].cssRules[0].style.border).toBe 'dashed'

        expect(stylesheetsChangedHandler).toHaveBeenCalled()

        stylesheetRemovedHandler.reset()
        stylesheetsChangedHandler.reset()
        fs.removeSync(userStylesheetPath)

      waitsFor ->
        themeManager.loadUserStylesheet.callCount is 2

      runs ->
        expect(stylesheetRemovedHandler).toHaveBeenCalled()
        expect(stylesheetRemovedHandler.argsForCall[0][0].cssRules[0].style.border).toBe 'dashed'
        expect($(document.body).css('border-style')).toBe 'none'
        expect(stylesheetsChangedHandler).toHaveBeenCalled()

  describe "when a non-existent theme is present in the config", ->
    beforeEach ->
      spyOn(console, 'warn')
      atom.config.set('core.themes', ['non-existent-dark-ui', 'non-existent-dark-syntax'])

      waitsForPromise ->
        themeManager.activateThemes()

    it 'uses the default dark UI and syntax themes and logs a warning', ->
      activeThemeNames = themeManager.getActiveNames()
      expect(console.warn.callCount).toBe 2
      expect(activeThemeNames.length).toBe(2)
      expect(activeThemeNames).toContain('atom-dark-ui')
      expect(activeThemeNames).toContain('atom-dark-syntax')

  describe "when in safe mode", ->
    beforeEach ->
      themeManager = new ThemeManager({packageManager: atom.packages, resourcePath, configDirPath, safeMode: true})

    describe 'when the enabled UI and syntax themes are bundled with Atom', ->
      beforeEach ->
        atom.config.set('core.themes', ['atom-light-ui', 'atom-dark-syntax'])

        waitsForPromise ->
          themeManager.activateThemes()

      it 'uses the enabled themes', ->
        activeThemeNames = themeManager.getActiveNames()
        expect(activeThemeNames.length).toBe(2)
        expect(activeThemeNames).toContain('atom-light-ui')
        expect(activeThemeNames).toContain('atom-dark-syntax')

    describe 'when the enabled UI and syntax themes are not bundled with Atom', ->
      beforeEach ->
        atom.config.set('core.themes', ['installed-dark-ui', 'installed-dark-syntax'])

        waitsForPromise ->
          themeManager.activateThemes()

      it 'uses the default dark UI and syntax themes', ->
        activeThemeNames = themeManager.getActiveNames()
        expect(activeThemeNames.length).toBe(2)
        expect(activeThemeNames).toContain('atom-dark-ui')
        expect(activeThemeNames).toContain('atom-dark-syntax')

    describe 'when the enabled UI theme is not bundled with Atom', ->
      beforeEach ->
        atom.config.set('core.themes', ['installed-dark-ui', 'atom-light-syntax'])

        waitsForPromise ->
          themeManager.activateThemes()

      it 'uses the default dark UI theme', ->
        activeThemeNames = themeManager.getActiveNames()
        expect(activeThemeNames.length).toBe(2)
        expect(activeThemeNames).toContain('atom-dark-ui')
        expect(activeThemeNames).toContain('atom-light-syntax')

    describe 'when the enabled syntax theme is not bundled with Atom', ->
      beforeEach ->
        atom.config.set('core.themes', ['atom-light-ui', 'installed-dark-syntax'])

        waitsForPromise ->
          themeManager.activateThemes()

      it 'uses the default dark syntax theme', ->
        activeThemeNames = themeManager.getActiveNames()
        expect(activeThemeNames.length).toBe(2)
        expect(activeThemeNames).toContain('atom-light-ui')
        expect(activeThemeNames).toContain('atom-dark-syntax')
