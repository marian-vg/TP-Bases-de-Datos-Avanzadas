import { useEffect, useRef } from 'react'

export function usePolling(callback: () => void | Promise<void>, interval: number = 2000) {
  const savedCallback = useRef(callback)
  useEffect(() => { savedCallback.current = callback }, [callback])

  useEffect(() => {
    void savedCallback.current()
    const id = setInterval(() => savedCallback.current(), interval)
    return () => clearInterval(id)
  }, [interval])
}
