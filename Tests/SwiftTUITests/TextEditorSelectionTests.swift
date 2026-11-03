import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextEditorSelectionTests {
  private final class EditorState {
    var text = ""
    var selection = 0..<0
    var writes: [String] = []
    /// Runs inside the text setter, after the editor's own write.
    var rewrite: ((EditorState) -> Void)?
  }

  private func render(
    _ state: EditorState,
    identity: Identity,
    registry: LocalKeyHandlerRegistry,
    renderer: DefaultRenderer = DefaultRenderer()
  ) -> DefaultRenderer {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity
    _ = renderer.render(
      TextEditor(
        text: Binding(
          get: { state.text },
          set: {
            state.writes.append("text")
            state.text = $0
            state.rewrite?(state)
          }
        ),
        selection: Binding(
          get: { state.selection },
          set: {
            state.writes.append("selection")
            state.selection = $0
          }
        )
      )
      .id(identity),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )
    return renderer
  }

  private func type(
    _ text: String,
    into identity: Identity,
    registry: LocalKeyHandlerRegistry
  ) {
    for character in text {
      #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character(character))))
    }
  }

  @Test("the selection binding follows typing and caret moves")
  func selectionFollowsEditing() {
    let state = EditorState()
    let identity = testIdentity("SelectionEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = render(state, identity: identity, registry: registry)
    defer { withExtendedLifetime(renderer) {} }

    type("abc", into: identity, registry: registry)
    #expect(state.selection == 3..<3)
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft)))
    #expect(state.selection == 2..<2)
    #expect(
      registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft, modifiers: .shift)))
    #expect(state.selection == 1..<2)
  }

  @Test("setting the selection places the caret")
  func callerSelectionPlacesTheCaret() {
    let state = EditorState()
    let identity = testIdentity("PlacedCaretEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = render(state, identity: identity, registry: registry)
    defer { withExtendedLifetime(renderer) {} }

    type("abc", into: identity, registry: registry)
    state.selection = 1..<1
    _ = render(state, identity: identity, registry: registry, renderer: renderer)
    type("x", into: identity, registry: registry)
    #expect(state.text == "axbc")
    #expect(state.selection == 2..<2)
  }

  @Test("a text setter that rewrites the text can also place the caret")
  func textSetterPlacesTheCaret() {
    let state = EditorState()
    let identity = testIdentity("RewritingEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = render(state, identity: identity, registry: registry)
    defer { withExtendedLifetime(renderer) {} }

    type("ab[1]cd", into: identity, registry: registry)
    state.selection = 5..<5
    _ = render(state, identity: identity, registry: registry, renderer: renderer)
    // Deleting into the bracketed token removes all of it and leaves the caret where it was.
    state.rewrite = { state in
      guard state.text == "ab[1cd" else { return }
      state.text = "abcd"
      state.selection = 2..<2
    }
    state.writes.removeAll()
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.backspace)))
    #expect(state.writes == ["selection", "text"])
    state.rewrite = nil
    _ = render(state, identity: identity, registry: registry, renderer: renderer)
    type("X", into: identity, registry: registry)
    #expect(state.text == "abXcd")
  }

  @Test("changing only the text keeps the caret at the end, as init(text:) does")
  func textChangeWithoutSelectionPutsTheCaretAtTheEnd() {
    let state = EditorState()
    let identity = testIdentity("ReplacedTextEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = render(state, identity: identity, registry: registry)
    defer { withExtendedLifetime(renderer) {} }

    type("abc", into: identity, registry: registry)
    state.text = "hello"
    _ = render(state, identity: identity, registry: registry, renderer: renderer)
    type("!", into: identity, registry: registry)
    #expect(state.text == "hello!")
  }

  @Test("a selection past the end of the text is clamped")
  func outOfRangeSelectionIsClamped() {
    let state = EditorState()
    let identity = testIdentity("ClampedEditor")
    let registry = LocalKeyHandlerRegistry()
    let renderer = render(state, identity: identity, registry: registry)
    defer { withExtendedLifetime(renderer) {} }

    state.text = "ab"
    state.selection = 9..<9
    _ = render(state, identity: identity, registry: registry, renderer: renderer)
    type("c", into: identity, registry: registry)
    #expect(state.text == "abc")
    #expect(state.selection == 3..<3)
  }
}
