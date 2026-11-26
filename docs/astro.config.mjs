// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
	site: 'https://hometv.nziranziza.dev',
	integrations: [
		starlight({
			title: 'HomeTV',
			customCss: ['./src/styles/custom.css'],
			components: { PageTitle: './src/components/PageTitle.astro' },
			logo: { light: './src/assets/logo-light.svg', dark: './src/assets/logo-dark.svg' },
			head: [
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' } },
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://hometv.nziranziza.dev/og.png' } },
				{ tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
				{ tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
				{ tag: 'meta', attrs: { property: 'og:image:alt', content: 'The HomeTV app icon' } },
				{ tag: 'meta', attrs: { name: 'twitter:image', content: 'https://hometv.nziranziza.dev/og.png' } },
			],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/Nziranziza/home-tv' }],
			editLink: { baseUrl: 'https://github.com/Nziranziza/home-tv/edit/main/docs/' },
			sidebar: [
				{ label: 'Overview', link: '/' },
				{
					label: 'User guide',
					items: [
						'guide/install',
						'guide/setup-and-addons',
						'guide/watch-now',
						'guide/titles-episodes-cast',
						'guide/search',
						'guide/playback',
						'guide/trakt-and-library',
						'guide/top-shelf-settings-faq',
					],
				},
				{
					label: 'Developers',
					items: [
						'developers/build-from-source',
						'developers/architecture',
						'developers/playback-architecture',
						'developers/contributing',
						'developers/licenses',
					],
				},
			],
		}),
	],
});
