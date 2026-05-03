import { chromium } from 'playwright'

async function run() {
  const browser = await chromium.launch()
  const page = await browser.newPage()
  page.on('console', msg => console.log('BROWSER CONSOLE:', msg.text()))
  page.on('pageerror', err => console.error('BROWSER ERROR:', err))
  
  await page.goto('http://localhost:5173/login')
  await page.fill('input[type="email"]', 'owner@test.com')
  await page.fill('input[type="password"]', 'password123')
  await page.click('button[type="submit"]')
  
  // wait 3 seconds
  await new Promise(r => setTimeout(r, 3000))
  
  console.log('Current URL:', page.url())
  const content = await page.content()
  
  if (content.includes('animate-spin')) {
    console.log('SPINNER FOUND!')
  }
  
  // print the main tags inside body
  const bodyHandle = await page.$('body')
  const html = await page.evaluate(body => body.innerHTML, bodyHandle)
  console.log('BODY HTML:', html)
  
  await browser.close()
}
run()
