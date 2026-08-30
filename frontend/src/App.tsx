import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { Chat } from '@/pages/Chat'

// Single route for the chat-only MVP -- react-router is here so a second
// route (e.g. a port-calls table view) is a `<Route>` away, not a rewrite.
function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Chat />} />
      </Routes>
    </BrowserRouter>
  )
}

export default App
