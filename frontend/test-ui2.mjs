import { chromium } from 'playwright'

async function run() {
  const browser = await chromium.launch()
  const context = await browser.newContext()
  const page = await context.newPage()
  page.on('console', msg => console.log('BROWSER CONSOLE:', msg.text()))
  page.on('pageerror', err => console.error('BROWSER ERROR:', err))
  
  await page.goto('http://localhost:5173/login')
  await page.fill('input[type="email"]', 'owner@test.com')
  await page.fill('input[type="password"]', 'password123')
  await page.click('button[type="submit"]')
  
  // wait 2 seconds for login to finish
  await new Promise(r => setTimeout(r, 2000))
  
  // Now navigate to /
  console.log('Navigating to / ...')
  await page.goto('http://localhost:5173/')
  
  // wait 4 seconds
  await new Promise(r => setTimeout(r, 4000))
  
  console.log('Current URL:', page.url())
  
  // print the main tags inside body
  const bodyHandle = await page.$('body')
  const html = await page.evaluate(body => body.innerHTML, bodyHandle)
  console.log('BODY HTML LENGTH:', html.length)
  if (html.includes('animate-spin')) console.log('SPINNER FOUND IN HTML!')
  if (html.includes('Dashboard')) console.log('DASHBOARD FOUND IN HTML!')
  
  await browser.close()
}
run()
