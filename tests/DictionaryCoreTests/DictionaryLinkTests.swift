import DictionaryCore
import Testing

struct DictionaryLinkTests {
  @Test(arguments: [
    "x-dictionary:r:dummy_plant:dummy.dictionary#xpointer(//*[@id='dummy_sense'])",
    "x-dictionary:r:dummy_plant:dummy.dictionary#xpointer(//*[@id='dummy_sense']):lumifern",
    "x-dictionary:r:dummy_plant:dummy.dictionary%23xpointer(//*%5B@id=%27dummy_sense%27%5D):lumifern",
  ])
  func sectionReference(_ address: String) {
    #expect(DictionaryLink(address) == .reference("dummy_plant", anchor: "dummy_sense"))
  }

  @Test func entryReference() {
    #expect(
      DictionaryLink("x-dictionary:r:dummy_plant:dummy.dictionary:lumifern")
        == .reference("dummy_plant", anchor: nil))
  }
}
